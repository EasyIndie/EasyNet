//go:build darwin && cgo

package statelab

import (
	"bytes"
	"encoding/binary"
	"io"
	"os"
	"strings"

	"golang.org/x/sys/unix"
)

// SQLiteStore owns root/lock descriptors, never a persistent native connection.
// Pathname VFS checks are not a sandbox against an adversarial same-UID process.
type SQLiteStore struct {
	locker        *JSONStore
	dir           string
	beforePublish func(*sqliteDB) error
	afterPublish  func() error
	beforeAck     func() error
}

func canonicalSQLiteRoot(dir string) string {
	if strings.HasPrefix(dir, "/tmp/") {
		return "/private" + dir
	}
	return dir
}
func (s *SQLiteStore) guard() error {
	if e := s.locker.guard(); e != nil {
		return e
	}
	var named unix.Stat_t
	if e := unix.Lstat(s.dir, &named); e != nil {
		return nativeError(e)
	}
	if !safeStat(&named, true, uint32(os.Geteuid())) || !sameInode(&named, &s.locker.rootStat) {
		return ErrLocationUnsafe
	}
	return nil
}
func sqliteInventory(root int, allowJournal bool) (map[string]unix.Stat_t, error) {
	fd, e := unix.Openat(root, ".", unix.O_RDONLY|unix.O_DIRECTORY|unix.O_NOFOLLOW|unix.O_CLOEXEC, 0)
	if e != nil {
		return nil, ErrIO
	}
	f := os.NewFile(uintptr(fd), "sqlite-inventory")
	names, e := f.Readdirnames(4)
	ce := f.Close()
	if e != nil && e != io.EOF || ce != nil {
		return nil, ErrIO
	}
	out := map[string]unix.Stat_t{}
	journal := false
	for _, name := range names {
		if name != sqliteName && name != lockName && name != sqliteJournal {
			return nil, ErrLocationUnsafe
		}
		var st unix.Stat_t
		if unix.Fstatat(root, name, &st, unix.AT_SYMLINK_NOFOLLOW) != nil {
			return nil, ErrIO
		}
		if !safeStat(&st, false, uint32(os.Geteuid())) {
			return nil, ErrLocationUnsafe
		}
		out[name] = st
		if name == sqliteJournal {
			journal = true
		}
	}
	if journal && !allowJournal {
		return nil, ErrIO
	}
	return out, nil
}
func (s *SQLiteStore) physical(fd int, allowJournal, header bool) error {
	if e := s.guard(); e != nil {
		return e
	}
	inventory, e := sqliteInventory(s.locker.root, allowJournal)
	if e != nil {
		return e
	}
	named, ok := inventory[sqliteName]
	if !ok {
		return ErrNotFound
	}
	if _, ok = inventory[lockName]; !ok {
		return ErrNotFound
	}
	var held unix.Stat_t
	if unix.Fstat(fd, &held) != nil {
		return ErrIO
	}
	if !safeStat(&held, false, uint32(os.Geteuid())) || !sameInode(&held, &named) {
		return ErrLocationUnsafe
	}
	if header {
		if held.Size < 4096 || held.Size > 1024*1024 || held.Size%4096 != 0 {
			return ErrCorrupt
		}
		var b [100]byte
		n, e := unix.Pread(fd, b[:], 0)
		if e != nil || n != len(b) {
			return ErrCorrupt
		}
		if !bytes.Equal(b[:16], []byte("SQLite format 3\x00")) || binary.BigEndian.Uint16(b[16:18]) != 4096 || b[18] != 1 || b[19] != 1 {
			return ErrCorrupt
		}
	}
	return nil
}
func (s *SQLiteStore) databaseFD(allowJournal, header bool) (int, error) {
	if e := s.guard(); e != nil {
		return -1, e
	}
	if _, e := sqliteInventory(s.locker.root, allowJournal); e != nil {
		return -1, e
	}
	fd, e := guardedFile(s.locker.root, sqliteName, unix.O_RDONLY)
	if e != nil {
		return -1, e
	}
	if e = s.physical(fd, allowJournal, header); e != nil {
		unix.Close(fd)
		return -1, e
	}
	return fd, nil
}
func (s *SQLiteStore) native(fd int, readonly, allowJournal bool) (*sqliteDB, error) {
	if e := s.physical(fd, allowJournal, !allowJournal); e != nil {
		return nil, e
	}
	d, e := openSQLite(s.dir+"/"+sqliteName, readonly)
	if e != nil {
		return nil, e
	}
	if e = s.physical(fd, allowJournal, !allowJournal); e != nil {
		d.close()
		return nil, e
	}
	return d, nil
}
func OpenSQLiteFixture(dir string, r Resolver) (*SQLiteStore, error) {
	root, st, e := openRoot(dir)
	if e != nil {
		return nil, e
	}
	lock, e := guardedFile(root, lockName, unix.O_RDWR)
	if e != nil {
		unix.Close(root)
		return nil, e
	}
	s := &SQLiteStore{locker: &JSONStore{root: root, lock: lock, rootStat: st, resolver: r}, dir: canonicalSQLiteRoot(dir)}
	if e = s.locker.acquire(false); e != nil {
		s.Close()
		return nil, e
	}
	fd, e := s.databaseFD(false, true)
	if fd >= 0 && unix.Close(fd) != nil && e == nil {
		e = ErrIO
	}
	unix.Flock(lock, unix.LOCK_UN)
	if e != nil {
		s.Close()
		return nil, e
	}
	return s, nil
}

// Seed never deletes after failure: callers own and inventory their fixture.
func SeedSQLiteFixture(dir string, seed Snapshot, r Resolver) error {
	return seedSQLiteFixture(dir, seed, r, nil)
}
func seedSQLiteFixture(dir string, seed Snapshot, r Resolver, probe func(int, int, int)) (result error) {
	phase := 100
	defer func() {
		if probe != nil {
			failed := 0
			if result != nil {
				failed = 1
			}
			probe(phase, failed, 0)
		}
	}()
	b, e := EncodeFixture(seed, r)
	if e != nil {
		return e
	}
	root, st, e := openRoot(dir)
	if e != nil {
		return e
	}
	defer unix.Close(root)
	inventory, e := sqliteInventory(root, false)
	if e != nil {
		return e
	}
	if len(inventory) != 0 {
		return ErrLocationUnsafe
	}
	lock, fd := -1, -1
	defer func() {
		if fd >= 0 {
			unix.Close(fd)
		}
		if lock >= 0 {
			unix.Close(lock)
		}
	}()
	for _, name := range []string{lockName, sqliteName} {
		created, err := unix.Openat(root, name, unix.O_RDWR|unix.O_CREAT|unix.O_EXCL|unix.O_NOFOLLOW|unix.O_CLOEXEC, 0600)
		if err != nil {
			return nativeError(err)
		}
		if name == lockName {
			lock = created
		} else {
			fd = created
		}
		var fst unix.Stat_t
		if unix.Fstat(created, &fst) != nil {
			return ErrIO
		}
		if !safeStat(&fst, false, uint32(os.Geteuid())) {
			return ErrLocationUnsafe
		}
	}
	s := &SQLiteStore{locker: &JSONStore{root: root, lock: lock, rootStat: st, resolver: r}, dir: canonicalSQLiteRoot(dir)}
	if e = s.locker.acquire(true); e != nil {
		return e
	}
	defer unix.Flock(lock, unix.LOCK_UN)
	if e = s.physical(fd, false, false); e != nil {
		return e
	}
	phase = 101
	d, e := openSQLiteWithProbe(s.dir+"/"+sqliteName, false, probe)
	if e != nil {
		return e
	}
	// One owned connection; all exits close it before descriptors/flock release.
	defer func() {
		if d.ptr != nil {
			d.close()
		}
	}()
	if e = s.physical(fd, false, false); e != nil {
		return e
	}
	phase = 102
	if e = d.settings(true, true); e != nil {
		return e
	}
	phase = 103
	if e = d.exec("BEGIN IMMEDIATE", nil, nil); e != nil {
		return e
	}
	phase = 104
	if e = d.exec(sqliteDDL, nil, nil); e == nil {
		phase = 105
		e = d.exec(sqliteInsert, []int64{int64(seed.SchemaVersion), int64(seed.Generation)}, b)
	}
	if e != nil {
		if d.exec("ROLLBACK", nil, nil) != nil || !d.autocommit() {
			return ErrCommitUnknown
		}
		if d.close() != nil || s.physical(fd, false, false) != nil {
			return ErrCommitUnknown
		}
		return e
	}
	phase = 106
	if e = d.exec("COMMIT", nil, nil); e != nil {
		return ErrCommitUnknown
	}
	phase = 107
	if d.close() != nil || s.physical(fd, false, true) != nil || unix.Fsync(root) != nil {
		return ErrCommitUnknown
	}
	return nil
}
func (s *SQLiteStore) diagnose(fd int) (Snapshot, error) {
	d, e := s.native(fd, true, false)
	if e != nil {
		return Snapshot{}, e
	}
	snap := Snapshot{}
	if e = d.settings(false, false); e == nil {
		snap, e = d.readSnapshot(s.locker.resolver, true)
	}
	closeErr := d.close()
	guardErr := s.physical(fd, false, true)
	if e != nil {
		return Snapshot{}, e
	}
	if closeErr != nil {
		return Snapshot{}, closeErr
	}
	if guardErr != nil {
		return Snapshot{}, guardErr
	}
	return snap, nil
}
func (s *SQLiteStore) load(migration bool) (Snapshot, error) {
	s.locker.mu.Lock()
	defer s.locker.mu.Unlock()
	if e := s.locker.acquire(false); e != nil {
		return Snapshot{}, e
	}
	defer unix.Flock(s.locker.lock, unix.LOCK_UN)
	fd, e := s.databaseFD(false, true)
	if e != nil {
		return Snapshot{}, e
	}
	defer unix.Close(fd)
	snap, e := s.diagnose(fd)
	if e != nil {
		return Snapshot{}, e
	}
	if migration {
		if snap.SchemaVersion != 0 {
			return Snapshot{}, ErrInvalid
		}
	} else if e = ValidateV1(snap, s.locker.resolver); e != nil {
		return Snapshot{}, e
	}
	return clone(snap), nil
}
func (s *SQLiteStore) Load() (Snapshot, error)             { return s.load(false) }
func (s *SQLiteStore) Snapshot() (Snapshot, error)         { return s.load(false) }
func (s *SQLiteStore) InspectMigration() (Snapshot, error) { return s.load(true) }
func (s *SQLiteStore) Close() error                        { return s.locker.Close() }
func (s *SQLiteStore) Commit(expected uint32, next Snapshot) (Snapshot, error) {
	return s.commit(expected, next, false)
}
func (s *SQLiteStore) CommitMigration(expected uint32, next Snapshot) (Snapshot, error) {
	return s.commit(expected, next, true)
}
func sqliteValidate(current, next Snapshot, expected uint32, r Resolver, migration bool) error {
	if migration {
		return ValidateMigration(current, next, expected, r)
	}
	return ValidateCommit(current, next, expected, r)
}

// Even failed BEGIN/configuration paths prove closure and no pending journal.
func (s *SQLiteStore) abort(d *sqliteDB, fd int, original error) error {
	rollback := error(nil)
	if !d.autocommit() {
		rollback = d.exec("ROLLBACK", nil, nil)
	}
	definite := rollback == nil && d.autocommit()
	closeErr := d.close()
	guardErr := s.physical(fd, false, true)
	if !definite || closeErr != nil || guardErr != nil {
		return ErrCommitUnknown
	}
	return original
}
func (s *SQLiteStore) commit(expected uint32, next Snapshot, migration bool) (Snapshot, error) {
	s.locker.mu.Lock()
	defer s.locker.mu.Unlock()
	if e := s.locker.acquire(true); e != nil {
		return Snapshot{}, e
	}
	defer unix.Flock(s.locker.lock, unix.LOCK_UN)
	fd, e := s.databaseFD(false, true)
	if e != nil {
		return Snapshot{}, e
	}
	defer unix.Close(fd)
	current, e := s.diagnose(fd)
	if e != nil {
		return Snapshot{}, e
	}
	next = clone(next)
	if e = sqliteValidate(current, next, expected, s.locker.resolver, migration); e != nil {
		return Snapshot{}, e
	}
	b, e := EncodeFixture(next, s.locker.resolver)
	if e != nil {
		return Snapshot{}, e
	}
	d, e := s.native(fd, false, false)
	if e != nil {
		return Snapshot{}, e
	}
	defer func() {
		if d.ptr != nil {
			d.close()
		}
	}()
	if e = d.settings(true, false); e != nil {
		return Snapshot{}, s.abort(d, fd, e)
	}
	if e = d.exec("BEGIN IMMEDIATE", nil, nil); e != nil {
		return Snapshot{}, s.abort(d, fd, e)
	}
	// No UPDATE has happened yet; preserve fixed validation/CAS errors.
	current, e = d.readSnapshot(s.locker.resolver, true)
	if e == nil {
		e = sqliteValidate(current, next, expected, s.locker.resolver, migration)
	}
	if e != nil {
		return Snapshot{}, s.abort(d, fd, e)
	}
	version := int64(1)
	if migration {
		version = 0
	}
	e = d.exec(sqliteUpdate, []int64{1, int64(next.Generation), version, int64(expected)}, b)
	if e == nil && d.changed() != 1 {
		e = ErrConflict
	}
	if e == nil && s.beforePublish != nil {
		e = s.beforePublish(d)
	}
	if e == nil {
		e = s.physical(fd, true, true)
	}
	if e != nil {
		rollback := d.exec("ROLLBACK", nil, nil)
		definite := rollback == nil && d.autocommit()
		closeErr := d.close()
		guardErr := s.physical(fd, false, true)
		if !definite || closeErr != nil || guardErr != nil {
			return Snapshot{}, ErrCommitUnknown
		}
		return Snapshot{}, ErrIO
	}
	// From invocation onwards, never retry: every failure is ambiguous.
	if d.exec("COMMIT", nil, nil) != nil {
		return Snapshot{}, ErrCommitUnknown
	}
	if s.afterPublish != nil && s.afterPublish() != nil {
		return Snapshot{}, ErrCommitUnknown
	}
	guardErr := s.physical(fd, false, true)
	closeErr := d.close()
	if guardErr != nil || closeErr != nil || s.physical(fd, false, true) != nil {
		return Snapshot{}, ErrCommitUnknown
	}
	if s.beforeAck != nil && s.beforeAck() != nil {
		return Snapshot{}, ErrCommitUnknown
	}
	committed, e := DecodeFixture(b)
	if e != nil {
		return Snapshot{}, ErrCommitUnknown
	}
	return committed, nil
}
