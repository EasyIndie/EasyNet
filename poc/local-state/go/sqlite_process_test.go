//go:build darwin && cgo

package statelab

import (
	"bufio"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/binary"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"testing"
	"time"

	"golang.org/x/sys/unix"
)

type sqliteLab struct {
	dir      string
	root     int
	original unix.Stat_t
	children []*sqliteChild
	seeded   bool
	preserve bool
}

func newSQLiteLab(t *testing.T) *sqliteLab {
	t.Helper()
	dir, e := os.MkdirTemp("/tmp", "easynet-state-lab-")
	if e != nil {
		t.Fatal("fixture mkdir")
	}
	root, st, e := openRoot(dir)
	if e != nil {
		os.Remove(dir)
		t.Fatal("fixture root")
	}
	l := &sqliteLab{dir: canonicalSQLiteRoot(dir), root: root, original: st}
	t.Cleanup(func() {
		for _, c := range l.children {
			c.reap(true)
		}
		if l.root >= 0 {
			if e := l.cleanup(); e != nil {
				t.Errorf("SQLite cleanup refused: %v", e)
			}
		}
	})
	return l
}
func (l *sqliteLab) guard() error {
	var held, named unix.Stat_t
	if l.root < 0 || unix.Fstat(l.root, &held) != nil {
		return ErrIO
	}
	if e := unix.Lstat(l.dir, &named); e != nil {
		return nativeError(e)
	}
	if !sameInode(&held, &l.original) || !sameInode(&named, &l.original) || !safeStat(&held, true, uint32(os.Geteuid())) || !safeStat(&named, true, uint32(os.Geteuid())) {
		return ErrLocationUnsafe
	}
	return nil
}

// Validate the ENTIRE inventory before deletion, including creator-recorded names.
// On refusal the held descriptor closes and every entry remains for diagnosis.
func (l *sqliteLab) cleanup() (err error) {
	defer func() {
		if l.root >= 0 {
			unix.Close(l.root)
			l.root = -1
		}
	}()
	for _, c := range l.children {
		if !c.waited {
			return ErrIO
		}
	}
	if l.preserve {
		return nil // Reaped children and deferred descriptor close; preserve every entry.
	}
	if e := l.guard(); e != nil {
		return e
	}
	inventory, e := sqliteInventory(l.root, true)
	if e != nil {
		return e
	}
	for name, old := range inventory {
		var st unix.Stat_t
		if unix.Fstatat(l.root, name, &st, unix.AT_SYMLINK_NOFOLLOW) != nil {
			return ErrIO
		}
		if !sameInode(&st, &old) || !safeStat(&st, false, uint32(os.Geteuid())) {
			return ErrLocationUnsafe
		}
	}
	for name, old := range inventory {
		if e = l.guard(); e != nil {
			return e
		}
		var st unix.Stat_t
		if unix.Fstatat(l.root, name, &st, unix.AT_SYMLINK_NOFOLLOW) != nil {
			return ErrIO
		}
		if !sameInode(&st, &old) || !safeStat(&st, false, uint32(os.Geteuid())) {
			return ErrLocationUnsafe
		}
		if unix.Unlinkat(l.root, name, 0) != nil {
			return ErrIO
		}
	}
	if e = l.guard(); e != nil {
		return e
	}
	if unix.Rmdir(l.dir) != nil {
		return ErrIO
	}
	return nil
}
func (l *sqliteLab) seed(t *testing.T, s Snapshot) {
	t.Helper()
	errCode(t, SeedSQLiteFixture(l.dir, s, ownedResolver()), nil)
	l.seeded = true
}
func openSQLiteLab(t *testing.T, l *sqliteLab, r Resolver) *SQLiteStore {
	t.Helper()
	s, e := OpenSQLiteFixture(l.dir, r)
	errCode(t, e, nil)
	t.Cleanup(func() {
		if !s.locker.closed {
			errCode(t, s.Close(), nil)
		}
	})
	return s
}
func sqliteFingerprint(t *testing.T, l *sqliteLab) string {
	t.Helper()
	errCode(t, l.guard(), nil)
	entries, e := os.ReadDir(l.dir)
	if e != nil {
		t.Fatal("fingerprint listing")
	}
	var b strings.Builder
	for _, entry := range entries {
		var st unix.Stat_t
		if unix.Fstatat(l.root, entry.Name(), &st, unix.AT_SYMLINK_NOFOLLOW) != nil {
			t.Fatal("fingerprint stat")
		}
		fmt.Fprintf(&b, "%s:%d:%d:%d:%d:", entry.Name(), st.Mode, st.Uid, st.Nlink, st.Size)
		if uint32(st.Mode)&unix.S_IFMT == unix.S_IFREG {
			fd, e := guardedFile(l.root, entry.Name(), unix.O_RDONLY)
			if e != nil {
				t.Fatal("fingerprint guard")
			}
			f := os.NewFile(uintptr(fd), "fingerprint")
			data, e := io.ReadAll(io.LimitReader(f, 1024*1024+1))
			ce := f.Close()
			if e != nil || ce != nil || len(data) > 1024*1024 {
				t.Fatal("fingerprint read")
			}
			fmt.Fprintf(&b, "%x", sha256.Sum256(data))
		}
		b.WriteByte('\n')
	}
	return b.String()
}
func sqlitePurity(t *testing.T, l *sqliteLab, want Snapshot) {
	t.Helper()
	s := openSQLiteLab(t, l, ownedResolver())
	baseline := sqliteFingerprint(t, l)
	for i := 0; i < 3; i++ {
		if want.SchemaVersion == 0 {
			got, e := s.InspectMigration()
			resultCode(t, got, e, nil)
			equalSnapshot(t, got, want)
		} else {
			for _, read := range []func() (Snapshot, error){s.Load, s.Snapshot} {
				got, e := read()
				resultCode(t, got, e, nil)
				equalSnapshot(t, got, want)
			}
		}
		if sqliteFingerprint(t, l) != baseline {
			t.Fatal("read changed physical baseline")
		}
	}
	t.Logf("read purity schema=%d generation=%d repetitions=3", want.SchemaVersion, want.Generation)
}

type sqliteChild struct {
	cmd             *exec.Cmd
	cancel          context.CancelFunc
	events, control *os.File
	reader          *bufio.Reader
	stdout, stderr  *boundedCapture
	waited, killed  bool
	waitErr         error
}

func sqliteScenario(s string) bool {
	switch s {
	case "writer-a", "writer-b", "migrator-a", "migrator-b", "normal-before", "normal-after", "normal-boundary", "migration-before", "migration-after", "migration-boundary", "early":
		return true
	default:
		return false
	}
}
func startSQLiteChild(t *testing.T, l *sqliteLab, scenario string) *sqliteChild {
	t.Helper()
	if !sqliteScenario(scenario) {
		t.Fatal("selector")
	}
	executable, e := os.Executable()
	if e != nil {
		t.Fatal("executable")
	}
	eventsR, eventsW, e := os.Pipe()
	if e != nil {
		t.Fatal("event pipe")
	}
	controlR, controlW, e := os.Pipe()
	if e != nil {
		eventsR.Close()
		eventsW.Close()
		t.Fatal("control pipe")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	cmd := exec.CommandContext(ctx, executable, "-test.run=^TestSQLiteOwnedHelper$", "-test.count=1")
	cmd.Env = []string{"LANG=C", "PATH=/usr/bin:/bin", "EASYNET_SQLITE_ROOT=" + l.dir, "EASYNET_SQLITE_SCENARIO=" + scenario}
	cmd.ExtraFiles = []*os.File{eventsW, controlR}
	cmd.WaitDelay = time.Second
	c := &sqliteChild{cmd: cmd, cancel: cancel, events: eventsR, control: controlW, stdout: &boundedCapture{}, stderr: &boundedCapture{}}
	cmd.Stdout, cmd.Stderr = c.stdout, c.stderr
	if e = cmd.Start(); e != nil {
		cancel()
		eventsR.Close()
		eventsW.Close()
		controlR.Close()
		controlW.Close()
		t.Fatal("child start")
	}
	eventsW.Close()
	controlR.Close()
	c.reader = bufio.NewReaderSize(eventsR, 64)
	l.children = append(l.children, c)
	t.Cleanup(func() { c.reap(true) })
	return c
}
func (c *sqliteChild) event(t *testing.T) string {
	t.Helper()
	if e := c.events.SetReadDeadline(time.Now().Add(5 * time.Second)); e != nil {
		t.Fatal("event deadline")
	}
	b, e := c.reader.ReadSlice('\n')
	if e != nil || len(b) > 32 {
		t.Fatal("bounded child event")
	}
	event := string(b)
	switch event {
	case "ready\n", "before\n", "after\n", "committed\n", "conflict\n", "early\n":
		return event
	}
	t.Fatal("unknown child event")
	return ""
}
func (c *sqliteChild) release(t *testing.T) {
	t.Helper()
	if e := c.control.SetWriteDeadline(time.Now().Add(time.Second)); e != nil {
		t.Fatal("control deadline")
	}
	if n, e := c.control.Write([]byte{'G'}); e != nil || n != 1 {
		t.Fatal("child control")
	}
}
func (c *sqliteChild) reap(kill bool) {
	if c.waited {
		return
	}
	if kill {
		if c.cmd.Process.Kill() == nil {
			c.killed = true
		}
	}
	c.waitErr = c.cmd.Wait()
	c.waited = true
	c.cancel()
	c.events.Close()
	c.control.Close()
}
func TestSQLiteOwnedHelper(t *testing.T) {
	scenario := os.Getenv("EASYNET_SQLITE_SCENARIO")
	if scenario == "" {
		return
	}
	if !sqliteScenario(scenario) {
		t.Fatal("helper selector")
	}
	dir := os.Getenv("EASYNET_SQLITE_ROOT")
	if !labRoot.MatchString(dir) {
		t.Fatal("helper root")
	}
	events := os.NewFile(3, "sqlite-events")
	control := os.NewFile(4, "sqlite-control")
	defer events.Close()
	defer control.Close()
	emit := func(event string) {
		if _, e := events.WriteString(event + "\n"); e != nil {
			t.Fatal("helper event")
		}
	}
	await := func() {
		var b [1]byte
		if n, e := control.Read(b[:]); e != nil || n != 1 || b[0] != 'G' {
			t.Fatal("helper control")
		}
	}
	if scenario == "early" {
		emit("early")
		return
	}
	s, e := OpenSQLiteFixture(dir, ownedResolver())
	errCode(t, e, nil)
	defer s.Close()
	migration := strings.HasPrefix(scenario, "migration") || strings.HasPrefix(scenario, "migrator")
	current, e := s.Load()
	if migration {
		current, e = s.InspectMigration()
	}
	resultCode(t, current, e, nil)
	next := addition("Alpha")
	if strings.HasSuffix(scenario, "-b") {
		next = addition("Beta")
	}
	if migration {
		next, e = StageMigration(current, ownedResolver())
		errCode(t, e, nil)
	}
	race := strings.HasPrefix(scenario, "writer") || strings.HasPrefix(scenario, "migrator")
	if race {
		emit("ready")
		await()
	} else {
		s.beforePublish = func(d *sqliteDB) error {
			if e := d.cacheflush(); e != nil {
				return e
			}
			emit("before")
			await()
			return nil
		}
		if strings.HasSuffix(scenario, "after") {
			s.afterPublish = func() error { emit("after"); await(); return nil }
		}
	}
	var got Snapshot
	if migration {
		got, e = s.CommitMigration(current.Generation, next)
	} else {
		got, e = s.Commit(current.Generation, next)
	}
	if e == ErrConflict && race {
		resultCode(t, got, e, ErrConflict)
		emit("conflict")
		return
	}
	resultCode(t, got, e, nil)
	equalSnapshot(t, got, next)
	emit("committed")
	if !race {
		await()
	} // Keep completed boundary children alive until owned Kill/Wait.
}
func (l *sqliteLab) hotJournal(t *testing.T) bool {
	t.Helper()
	inventory, e := sqliteInventory(l.root, true)
	errCode(t, e, nil)
	st, ok := inventory[sqliteJournal]
	if !ok {
		return false
	}
	if st.Size <= 512 || st.Size > 1024*1024 {
		t.Fatal("journal size")
	}
	fd, e := guardedFile(l.root, sqliteJournal, unix.O_RDONLY)
	errCode(t, e, nil)
	var b [28]byte
	n, readErr := unix.Pread(fd, b[:], 0)
	ce := unix.Close(fd)
	if readErr != nil || ce != nil || n != len(b) {
		t.Fatal("journal header read")
	}
	magic := []byte{0xd9, 0xd5, 0x05, 0xf9, 0x20, 0xa1, 0x63, 0xd7}
	sector := binary.BigEndian.Uint32(b[20:24])
	if !bytes.Equal(b[:8], magic) || binary.BigEndian.Uint32(b[8:12]) == 0 || binary.BigEndian.Uint32(b[16:20]) == 0 || sector < 512 || sector > 65536 || sector&(sector-1) != 0 || binary.BigEndian.Uint32(b[24:28]) != 4096 {
		t.Fatal("required actual hot journal missing")
	}
	t.Logf("observed hot journal bytes=%d sector=%d", st.Size, sector)
	return true
}

// Only the creator's reaped killed child can authorize this explicit recovery.
func recoverSQLiteOwnedCrashFixture(t *testing.T, l *sqliteLab, c *sqliteChild, old, next Snapshot) Snapshot {
	t.Helper()
	wasPreserved := l.preserve
	l.preserve = true // Any Fatal during recovery leaves the entire fixture intact.
	if !l.seeded || !c.waited || !c.killed {
		t.Fatal("recovery provenance")
	}
	known := false
	for _, owned := range l.children {
		if owned == c {
			known = true
		}
	}
	if !known {
		t.Fatal("recovery child ownership")
	}
	errCode(t, l.guard(), nil)
	lock, e := guardedFile(l.root, lockName, unix.O_RDWR)
	errCode(t, e, nil)
	s := &SQLiteStore{locker: &JSONStore{root: l.root, lock: lock, rootStat: l.original, resolver: ownedResolver()}, dir: l.dir}
	defer unix.Close(lock)
	errCode(t, s.locker.acquire(true), nil)
	defer unix.Flock(lock, unix.LOCK_UN)
	before := sqliteFingerprint(t, l)
	fd, e := s.databaseFD(true, true)
	errCode(t, e, nil)
	defer unix.Close(fd)
	d, e := s.native(fd, false, true)
	errCode(t, e, nil)
	defer func() {
		if d.ptr != nil {
			d.close()
		}
	}()
	errCode(t, d.settings(true, false), nil)
	recovered, e := d.readSnapshot(ownedResolver(), true)
	resultCode(t, recovered, e, nil)
	if e = l.acceptRecovered(recovered, old, next); e != nil {
		t.Fatal("recovery outside exact old/successor")
	}
	inventory, e := sqliteInventory(l.root, true)
	errCode(t, e, nil)
	if _, ok := inventory[sqliteJournal]; ok {
		errCode(t, d.exec("BEGIN IMMEDIATE", nil, nil), nil)
		errCode(t, d.exec(sqliteNoop, nil, nil), nil)
		errCode(t, d.exec("COMMIT", nil, nil), nil)
		again, e := d.readSnapshot(ownedResolver(), true)
		resultCode(t, again, e, nil)
		equalSnapshot(t, again, recovered)
	}
	errCode(t, d.close(), nil)
	errCode(t, s.physical(fd, false, true), nil)
	after := sqliteFingerprint(t, l)
	t.Logf("owned recovery schema=%d generation=%d physicalChanged=%t", recovered.SchemaVersion, recovered.Generation, before != after)
	l.preserve = wasPreserved
	return recovered
}
func (l *sqliteLab) acceptRecovered(got, old, next Snapshot) error {
	if !logicalEqual(got, old) && !logicalEqual(got, next) {
		l.preserve = true
		return ErrCorrupt
	}
	return nil
}

func TestSQLiteRecoveryRefusalPreserves(t *testing.T) {
	l := newSQLiteLab(t)
	old, next := emptyFixture(), addition("Alpha")
	l.seed(t, old)
	baseline := sqliteFingerprint(t, l)
	errCode(t, l.acceptRecovered(addition("Beta"), old, next), ErrCorrupt)
	errCode(t, l.cleanup(), nil)
	if l.root != -1 {
		t.Fatal("preserved fixture descriptor not closed")
	}
	root, st, e := openRoot(l.dir)
	errCode(t, e, nil)
	l.root = root
	if !sameInode(&st, &l.original) || sqliteFingerprint(t, l) != baseline {
		t.Fatal("refused recovery changed fixture")
	}
	l.preserve = false // Creator-only teardown after preservation assertions.
}

func TestSQLiteProcessCAS(t *testing.T) {
	for _, migration := range []bool{false, true} {
		name := "writer"
		seed := emptyFixture()
		prefix := "writer"
		if migration {
			name = "migration"
			seed = migrationFixture()
			prefix = "migrator"
		}
		t.Run(name, func(t *testing.T) {
			l := newSQLiteLab(t)
			l.seed(t, seed)
			a := startSQLiteChild(t, l, prefix+"-a")
			b := startSQLiteChild(t, l, prefix+"-b")
			if a.event(t) != "ready\n" || b.event(t) != "ready\n" {
				t.Fatal("CAS barrier")
			}
			a.release(t)
			b.release(t)
			ea, eb := a.event(t), b.event(t)
			a.reap(false)
			b.reap(false)
			if a.waitErr != nil || b.waitErr != nil {
				t.Fatal("CAS child exit")
			}
			if !(ea == "committed\n" && eb == "conflict\n" || eb == "committed\n" && ea == "conflict\n") {
				t.Fatal("CAS whole winner/conflict")
			}
			want := addition("Alpha")
			if ea == "conflict\n" {
				want = addition("Beta")
			}
			if migration {
				var e error
				want, e = StageMigration(seed, ownedResolver())
				errCode(t, e, nil)
			}
			sqlitePurity(t, l, want)
			t.Logf("children=2 committed=1 conflict=1 generation=%d", want.Generation)
		})
	}
}
func TestSQLiteProcessCrashes(t *testing.T) {
	for _, mode := range []string{"normal", "migration"} {
		for _, phase := range []string{"before", "after", "boundary"} {
			repetitions := 2
			if phase == "boundary" {
				repetitions = 3
			}
			for trial := 0; trial < repetitions; trial++ {
				t.Run(fmt.Sprintf("%s-%s-%d", mode, phase, trial), func(t *testing.T) {
					l := newSQLiteLab(t)
					old := emptyFixture()
					next := addition("Alpha")
					if mode == "migration" {
						old = migrationFixture()
						var e error
						next, e = StageMigration(old, ownedResolver())
						errCode(t, e, nil)
					}
					l.seed(t, old)
					l.preserve = true // Missing-hot, barrier, recovery or purity failures preserve.
					c := startSQLiteChild(t, l, mode+"-"+phase)
					if c.event(t) != "before\n" {
						t.Fatal("precommit pause")
					}
					if phase == "after" {
						c.release(t)
						if c.event(t) != "after\n" {
							t.Fatal("postcommit pause")
						}
					} else if phase == "boundary" {
						c.release(t)
					}
					c.reap(true)
					if !c.killed {
						t.Fatal("owned kill failed")
					}
					hot := l.hotJournal(t)
					if phase == "before" && !hot {
						t.Fatal("deterministic before requires observed hot journal")
					}
					if phase == "after" && hot {
						t.Fatal("after retained journal")
					}
					got := recoverSQLiteOwnedCrashFixture(t, l, c, old, next)
					if phase == "before" {
						equalSnapshot(t, got, old)
					} else if phase == "after" {
						equalSnapshot(t, got, next)
					} else {
						if !logicalEqual(got, old) && !logicalEqual(got, next) {
							t.Fatal("boundary mixed snapshot")
						}
						if !hot {
							equalSnapshot(t, got, next)
							t.Log("boundary complete commit without journal")
						}
					}
					sqlitePurity(t, l, got)
					t.Logf("kill mode=%s phase=%s trial=%d generation=%d hot=%t logs=%d/%d", mode, phase, trial, got.Generation, hot, c.stdout.size(), c.stderr.size())
					l.preserve = false // Only fully qualified trials permit creator cleanup.
				})
			}
		}
	}
}
func TestSQLiteChildEarlyReap(t *testing.T) {
	l := newSQLiteLab(t)
	l.seed(t, emptyFixture())
	c := startSQLiteChild(t, l, "early")
	if c.event(t) != "early\n" {
		t.Fatal("early child")
	}
	c.reap(false)
	if !c.waited || c.waitErr != nil || c.stdout.size() > 4096 || c.stderr.size() > 4096 {
		t.Fatal("early reap/log bounds")
	}
}
