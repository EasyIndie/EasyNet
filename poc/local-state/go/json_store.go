//go:build darwin || linux

package statelab

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"io"
	"os"
	"regexp"
	"sync"
	"time"

	"golang.org/x/sys/unix"
)

const stateName = "state.json"
const lockName = "state.lock"

var labRoot = regexp.MustCompile(`^/(private/)?tmp/easynet-state-lab-[A-Za-z0-9_-]{1,64}$`)

// JSONStore is an owned fixture adapter, not a production storage API.
// The root and lock descriptors live until Close; no state descriptor is retained.
type JSONStore struct {
	mu            sync.Mutex
	root          int
	lock          int
	rootStat      unix.Stat_t
	resolver      Resolver
	closed        bool
	beforePublish func() error
	afterPublish  func() error
	beforeAck     func() error
}

func safeStat(st *unix.Stat_t, directory bool, uid uint32) bool {
	kind, mode := uint32(unix.S_IFREG), uint32(0600)
	if directory {
		kind, mode = unix.S_IFDIR, 0700
	}
	return st.Uid == uid && uint32(st.Mode)&unix.S_IFMT == kind && uint32(st.Mode)&07777 == mode && (directory || st.Nlink == 1)
}
func sameInode(a, b *unix.Stat_t) bool { return a.Dev == b.Dev && a.Ino == b.Ino }
func nativeError(err error) error {
	if errors.Is(err, unix.ENOENT) {
		return ErrNotFound
	}
	if errors.Is(err, unix.ELOOP) || errors.Is(err, unix.ENOTDIR) {
		return ErrLocationUnsafe
	}
	return ErrIO
}
func openRoot(dir string) (int, unix.Stat_t, error) {
	var st unix.Stat_t
	// Reject personal/relative/traversal locations before any filesystem call.
	if os.Geteuid() == 0 || !labRoot.MatchString(dir) {
		return -1, st, ErrLocationUnsafe
	}
	fd, err := unix.Open(dir, unix.O_RDONLY|unix.O_DIRECTORY|unix.O_NOFOLLOW|unix.O_CLOEXEC, 0)
	if err != nil {
		return -1, st, nativeError(err)
	}
	if unix.Fstat(fd, &st) != nil {
		unix.Close(fd)
		return -1, st, ErrIO
	}
	if !safeStat(&st, true, uint32(os.Geteuid())) {
		unix.Close(fd)
		return -1, st, ErrLocationUnsafe
	}
	return fd, st, nil
}
func guardedFile(root int, name string, flags int) (int, error) {
	fd, err := unix.Openat(root, name, flags|unix.O_NOFOLLOW|unix.O_CLOEXEC|unix.O_NONBLOCK, 0)
	if err != nil {
		return -1, nativeError(err)
	}
	var st unix.Stat_t
	if unix.Fstat(fd, &st) != nil {
		unix.Close(fd)
		return -1, ErrIO
	}
	if !safeStat(&st, false, uint32(os.Geteuid())) {
		unix.Close(fd)
		return -1, ErrLocationUnsafe
	}
	return fd, nil
}

// SeedJSONFixture requires an existing empty owned directory. It never repairs
// permissions or removes entries that it did not create.
func SeedJSONFixture(dir string, seed Snapshot, r Resolver) error {
	root, _, err := openRoot(dir)
	if err != nil {
		return err
	}
	defer unix.Close(root)
	b, err := EncodeFixture(seed, r)
	if err != nil {
		return err
	}
	dup, err := unix.Dup(root)
	if err != nil {
		return ErrIO
	}
	listing := os.NewFile(uintptr(dup), "owned-root")
	names, readErr := listing.Readdirnames(1)
	closeErr := listing.Close()
	if len(names) != 0 {
		return ErrLocationUnsafe
	}
	if readErr != io.EOF || closeErr != nil {
		return ErrIO
	}
	created := []string{}
	complete := false
	defer func() {
		if !complete {
			for _, name := range created {
				_ = unix.Unlinkat(root, name, 0)
			}
		}
	}()
	for _, name := range []string{lockName, stateName} {
		fd, e := unix.Openat(root, name, unix.O_WRONLY|unix.O_CREAT|unix.O_EXCL|unix.O_NOFOLLOW|unix.O_CLOEXEC, 0600)
		if e != nil {
			return nativeError(e)
		}
		created = append(created, name)
		var st unix.Stat_t
		if unix.Fstat(fd, &st) != nil {
			unix.Close(fd)
			return ErrIO
		}
		if !safeStat(&st, false, uint32(os.Geteuid())) {
			unix.Close(fd)
			return ErrLocationUnsafe
		}
		f := os.NewFile(uintptr(fd), "owned-seed")
		if name == stateName {
			n, e := f.Write(b)
			if e != nil || n != len(b) {
				f.Close()
				return ErrIO
			}
		}
		e = f.Sync()
		ce := f.Close()
		if e != nil || ce != nil {
			return ErrIO
		}
	}
	if unix.Fsync(root) != nil {
		return ErrIO
	}
	complete = true
	return nil
}

// OpenJSONFixture opens existing descriptors only. It does not read, seed,
// initialize, migrate, or repair the state file.
func OpenJSONFixture(dir string, r Resolver) (*JSONStore, error) {
	root, st, err := openRoot(dir)
	if err != nil {
		return nil, err
	}
	lock, err := guardedFile(root, lockName, unix.O_RDWR)
	if err != nil {
		unix.Close(root)
		return nil, err
	}
	state, err := guardedFile(root, stateName, unix.O_RDONLY)
	if err != nil {
		unix.Close(lock)
		unix.Close(root)
		return nil, err
	}
	if unix.Close(state) != nil {
		unix.Close(lock)
		unix.Close(root)
		return nil, ErrIO
	}
	return &JSONStore{root: root, lock: lock, rootStat: st, resolver: r}, nil
}
func (s *JSONStore) guard() error {
	if s.closed {
		return ErrIO
	}
	var root, held, named unix.Stat_t
	if unix.Fstat(s.root, &root) != nil || unix.Fstat(s.lock, &held) != nil {
		return ErrIO
	}
	if !sameInode(&root, &s.rootStat) || !safeStat(&root, true, uint32(os.Geteuid())) || !safeStat(&held, false, uint32(os.Geteuid())) {
		return ErrLocationUnsafe
	}
	if e := unix.Fstatat(s.root, lockName, &named, unix.AT_SYMLINK_NOFOLLOW); e != nil {
		return nativeError(e)
	}
	if !safeStat(&named, false, uint32(os.Geteuid())) || !sameInode(&held, &named) {
		return ErrLocationUnsafe
	}
	return nil
}
func (s *JSONStore) acquire(exclusive bool) error {
	if err := s.guard(); err != nil {
		return err
	}
	flag := unix.LOCK_SH
	if exclusive {
		flag = unix.LOCK_EX
	}
	deadline := time.Now().Add(2 * time.Second)
	for {
		e := unix.Flock(s.lock, flag|unix.LOCK_NB)
		if e == nil {
			break
		}
		if e != unix.EWOULDBLOCK && e != unix.EAGAIN && e != unix.EINTR {
			return ErrIO
		}
		if !time.Now().Before(deadline) {
			return ErrIO
		}
		time.Sleep(10 * time.Millisecond)
	}
	// A waiter may have acquired an unlinked/replaced lock inode. Revalidate
	// AFTER flock, before state access, and release even on a failed guard.
	if err := s.guard(); err != nil {
		_ = unix.Flock(s.lock, unix.LOCK_UN)
		return err
	}
	return nil
}
func (s *JSONStore) read() (Snapshot, error) {
	fd, err := guardedFile(s.root, stateName, unix.O_RDONLY)
	if err != nil {
		return Snapshot{}, err
	}
	f := os.NewFile(uintptr(fd), "owned-state")
	b, e := io.ReadAll(io.LimitReader(f, maxFixture+1))
	ce := f.Close()
	if e != nil || ce != nil {
		return Snapshot{}, ErrIO
	}
	return DecodeFixture(b)
}
func (s *JSONStore) load(migration bool) (Snapshot, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.acquire(false); err != nil {
		return Snapshot{}, err
	}
	defer unix.Flock(s.lock, unix.LOCK_UN)
	snap, err := s.read()
	if err != nil {
		return Snapshot{}, err
	}
	if migration {
		if snap.SchemaVersion != 0 {
			return Snapshot{}, ErrInvalid
		}
		_, err = EncodeFixture(snap, s.resolver)
	} else {
		err = ValidateV1(snap, s.resolver)
	}
	if err != nil {
		return Snapshot{}, err
	}
	return clone(snap), nil
}
func (s *JSONStore) Load() (Snapshot, error)             { return s.load(false) }
func (s *JSONStore) Snapshot() (Snapshot, error)         { return s.load(false) }
func (s *JSONStore) InspectMigration() (Snapshot, error) { return s.load(true) }
func (s *JSONStore) Commit(expected uint32, next Snapshot) (Snapshot, error) {
	return s.commit(expected, next, false)
}
func (s *JSONStore) CommitMigration(expected uint32, staged Snapshot) (Snapshot, error) {
	return s.commit(expected, staged, true)
}
func (s *JSONStore) commit(expected uint32, next Snapshot, migration bool) (Snapshot, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.acquire(true); err != nil {
		return Snapshot{}, err
	}
	defer unix.Flock(s.lock, unix.LOCK_UN)
	current, err := s.read()
	if err != nil {
		return Snapshot{}, err
	}
	next = clone(next)
	if migration {
		err = ValidateMigration(current, next, expected, s.resolver)
	} else {
		err = ValidateCommit(current, next, expected, s.resolver)
	}
	if err != nil {
		return Snapshot{}, err
	}
	b, err := EncodeFixture(next, s.resolver)
	if err != nil {
		return Snapshot{}, err
	}
	if err = s.publish(b); err != nil {
		return Snapshot{}, err
	}
	// Return the canonical encoded snapshot; no aliases to the caller survive.
	committed, err := DecodeFixture(b)
	if err != nil {
		return Snapshot{}, ErrCommitUnknown
	}
	return committed, nil
}
func (s *JSONStore) publish(b []byte) error {
	var random [16]byte
	if _, e := rand.Read(random[:]); e != nil {
		return ErrIO
	}
	name := ".stage-" + hex.EncodeToString(random[:])
	fd, err := unix.Openat(s.root, name, unix.O_WRONLY|unix.O_CREAT|unix.O_EXCL|unix.O_NOFOLLOW|unix.O_CLOEXEC, 0600)
	if err != nil {
		return ErrIO
	}
	defer unix.Unlinkat(s.root, name, 0)
	var st unix.Stat_t
	if unix.Fstat(fd, &st) != nil {
		unix.Close(fd)
		return ErrIO
	}
	if !safeStat(&st, false, uint32(os.Geteuid())) {
		unix.Close(fd)
		return ErrLocationUnsafe
	}
	f := os.NewFile(uintptr(fd), "owned-stage")
	n, e := f.Write(b)
	if e != nil || n != len(b) {
		f.Close()
		return ErrIO
	}
	e = f.Sync()
	ce := f.Close()
	if e != nil || ce != nil {
		return ErrIO
	}
	if s.beforePublish != nil && s.beforePublish() != nil {
		return ErrIO
	}
	// Check the lock and destination again at the final publication boundary.
	if e = s.guard(); e != nil {
		return e
	}
	state, e := guardedFile(s.root, stateName, unix.O_RDONLY)
	if e != nil {
		return e
	}
	if unix.Close(state) != nil {
		return ErrIO
	}
	// From the invocation of rename onward, any failure is conservatively
	// ambiguous; clients must reload, never replay automatically.
	if unix.Renameat(s.root, name, s.root, stateName) != nil {
		return ErrCommitUnknown
	}
	if s.afterPublish != nil && s.afterPublish() != nil {
		return ErrCommitUnknown
	}
	if unix.Fsync(s.root) != nil {
		return ErrCommitUnknown
	}
	if s.beforeAck != nil && s.beforeAck() != nil {
		return ErrCommitUnknown
	}
	return nil
}
func (s *JSONStore) Close() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return ErrIO
	}
	s.closed = true
	a, b := unix.Close(s.lock), unix.Close(s.root)
	if a != nil || b != nil {
		return ErrIO
	}
	return nil
}
