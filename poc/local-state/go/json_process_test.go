//go:build darwin || linux

package statelab

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"testing"
	"time"

	"golang.org/x/sys/unix"
)

type ownedLab struct {
	dir      string
	names    map[string]bool
	root     int
	original unix.Stat_t
	children []*ownedChild
}

func newLab(t *testing.T) *ownedLab {
	t.Helper()
	if os.Geteuid() == 0 {
		t.Fatal("owned nonroot host required")
	}
	dir, e := os.MkdirTemp("/tmp", "easynet-state-lab-")
	if e != nil {
		t.Fatal("fixture mkdir failed")
	}
	root, st, e := openRoot(dir)
	if e != nil {
		os.Remove(dir)
		t.Fatal("owned root descriptor failed")
	}
	l := &ownedLab{dir: dir, names: map[string]bool{}, root: root, original: st}
	t.Cleanup(func() {
		// Registered before children: testing's LIFO cleanup reaps every child
		// before this descriptor-rooted orphan scan, including early Fatal paths.
		if _, e := l.cleanupStages(); e != nil {
			t.Errorf("owned orphan cleanup refused: %v", e) // Fixed ErrorCode only.
			unix.Close(l.root)
			return // Preserve the entire fixture after any inventory/guard refusal.
		}
		for name := range l.names {
			if ownedStagePattern.MatchString(name) {
				continue
			} // Only cleanupStages may remove staging entries.
			var st unix.Stat_t
			e := unix.Fstatat(l.root, name, &st, unix.AT_SYMLINK_NOFOLLOW)
			if e == unix.ENOENT {
				continue
			}
			if e != nil {
				t.Error("owned cleanup stat failed")
				continue
			}
			flag := 0
			if uint32(st.Mode)&unix.S_IFMT == unix.S_IFDIR {
				flag = unix.AT_REMOVEDIR
			}
			if unix.Unlinkat(l.root, name, flag) != nil {
				t.Error("owned cleanup failed")
			}
		}
		unix.Close(l.root)
		if e := os.Remove(l.dir); e != nil {
			t.Error("owned root cleanup failed")
		}
	})
	return l
}

// cleanupStages inventories only the original root after ALL children are joined.
// Validation completes before any deletion; unknown/unsafe entries are preserved.
func (l *ownedLab) cleanupStages() ([]string, error) {
	for _, c := range l.children {
		if !c.waited {
			return nil, ErrIO
		}
	}
	var root unix.Stat_t
	if unix.Fstat(l.root, &root) != nil {
		return nil, ErrIO
	}
	if !sameInode(&root, &l.original) || !safeStat(&root, true, uint32(os.Geteuid())) {
		return nil, ErrLocationUnsafe
	}
	// An explicitly removed empty test root cannot contain orphan stages.
	if root.Nlink == 0 {
		return nil, nil
	}
	fd, e := unix.Openat(l.root, ".", unix.O_RDONLY|unix.O_DIRECTORY|unix.O_NOFOLLOW|unix.O_CLOEXEC, 0)
	if e != nil {
		return nil, ErrIO
	}
	listing := os.NewFile(uintptr(fd), "owned-cleanup-root")
	names, e := listing.Readdirnames(-1)
	ce := listing.Close()
	if e != nil || ce != nil {
		return nil, ErrIO
	}
	stages := []string{}
	stats := map[string]unix.Stat_t{}
	for _, name := range names {
		if !ownedStagePattern.MatchString(name) {
			if !l.names[name] {
				return nil, ErrLocationUnsafe
			}
			continue
		}
		var st unix.Stat_t
		if unix.Fstatat(l.root, name, &st, unix.AT_SYMLINK_NOFOLLOW) != nil {
			return nil, ErrIO
		}
		if !safeStat(&st, false, uint32(os.Geteuid())) {
			return nil, ErrLocationUnsafe
		}
		stages = append(stages, name)
		stats[name] = st
	}
	for _, name := range stages {
		var st unix.Stat_t
		old := stats[name]
		if unix.Fstatat(l.root, name, &st, unix.AT_SYMLINK_NOFOLLOW) != nil {
			return nil, ErrIO
		}
		if !sameInode(&st, &old) || !safeStat(&st, false, uint32(os.Geteuid())) {
			return nil, ErrLocationUnsafe
		}
		l.names[name] = true
		if unix.Unlinkat(l.root, name, 0) != nil {
			return nil, ErrIO
		}
	}
	return stages, nil
}
func (l *ownedLab) seed(t *testing.T, s Snapshot) {
	t.Helper()
	errCode(t, SeedJSONFixture(l.dir, s, ownedResolver()), nil)
	l.names[stateName], l.names[lockName] = true, true
}

// boundedCapture continues draining after its retained 4096-byte prefix is full.
type boundedCapture struct {
	mu   sync.Mutex
	data []byte
}

func (b *boundedCapture) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	n := len(p)
	room := 4096 - len(b.data)
	if room > 0 {
		if len(p) > room {
			p = p[:room]
		}
		b.data = append(b.data, p...)
	}
	return n, nil
}
func (b *boundedCapture) size() int { b.mu.Lock(); defer b.mu.Unlock(); return len(b.data) }

type ownedChild struct {
	cmd            *exec.Cmd
	cancel         context.CancelFunc
	events         *os.File
	control        *os.File
	reader         *bufio.Reader
	stdout, stderr *boundedCapture
	waited         bool
}

func startOwnedChild(t *testing.T, l *ownedLab, scenario string) *ownedChild {
	t.Helper()
	exe, e := os.Executable()
	if e != nil {
		t.Fatal("owned executable missing")
	}
	eventRead, eventWrite, e := os.Pipe()
	if e != nil {
		t.Fatal("event pipe failed")
	}
	controlRead, controlWrite, e := os.Pipe()
	if e != nil {
		eventRead.Close()
		eventWrite.Close()
		t.Fatal("control pipe failed")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	out, errOut := &boundedCapture{}, &boundedCapture{}
	cmd := exec.CommandContext(ctx, exe, "-test.run=^TestJSONOwnedChild$", "-test.timeout=3s")
	cmd.WaitDelay = time.Second
	cmd.Env = []string{"LANG=C", "PATH=/usr/bin:/bin", "EASYNET_JSON_LAB_ROOT=" + l.dir, "EASYNET_JSON_LAB_SCENARIO=" + scenario}
	cmd.ExtraFiles = []*os.File{eventWrite, controlRead}
	cmd.Stdout = out
	cmd.Stderr = errOut
	c := &ownedChild{cmd: cmd, cancel: cancel, events: eventRead, control: controlWrite, reader: bufio.NewReader(eventRead), stdout: out, stderr: errOut}
	e = cmd.Start()
	eventWrite.Close()
	controlRead.Close()
	if e != nil {
		cancel()
		eventRead.Close()
		controlWrite.Close()
		t.Fatal("owned child start failed")
	}
	l.children = append(l.children, c)
	t.Cleanup(func() {
		if !c.waited {
			c.killAndReap(t)
		}
		c.events.Close()
		c.control.Close()
		c.cancel()
	})
	return c
}
func (c *ownedChild) event(t *testing.T, want string) {
	t.Helper()
	type answer struct {
		s string
		e error
	}
	done := make(chan answer, 1)
	go func() { b, e := c.reader.ReadSlice('\n'); done <- answer{string(b), e} }()
	select {
	case a := <-done:
		if a.e != nil || a.s != want+"\n" {
			t.Fatal("unexpected owned stage acknowledgement")
		}
	case <-time.After(2 * time.Second):
		// Close the owned reader, then join its goroutine before unwinding.
		c.events.Close()
		<-done
		t.Fatal("owned stage deadline")
	}
}
func (c *ownedChild) release(t *testing.T) {
	t.Helper()
	n, e := c.control.Write([]byte("GO\n"))
	if e != nil || n != 3 {
		t.Fatal("owned barrier release failed")
	}
}
func (c *ownedChild) reap(t *testing.T, success bool) {
	t.Helper()
	if c.waited {
		t.Fatal("double wait")
	}
	e := c.cmd.Wait()
	c.waited = true
	c.cancel()
	if success && e != nil {
		t.Fatal("owned child did not finish")
	}
	if c.stdout.size() > 4096 || c.stderr.size() > 4096 {
		t.Fatal("capture bound exceeded")
	}
}
func (c *ownedChild) killAndReap(t *testing.T) {
	t.Helper()
	if c.waited {
		return
	}
	// Only the process returned by this harness's Start can be killed here.
	e := c.cmd.Process.Kill()
	if e != nil && !errors.Is(e, os.ErrProcessDone) {
		t.Error("owned kill failed")
	}
	c.reap(t, false)
}
func childCandidate(id string) Snapshot {
	s := addition(id)
	h := "a"
	if id == "Beta" {
		h = "b"
	}
	s.Operations = []Operation{{"Operation" + id, id, "sha256:" + strings.Repeat(h, 64), "unknown"}}
	return s
}

// No init/TestMain exists: the compile-only gate cannot create fixtures/children.
// This helper accepts only fixed owned scenarios and inherited owned pipe FDs.
func TestJSONOwnedChild(t *testing.T) {
	root := os.Getenv("EASYNET_JSON_LAB_ROOT")
	scenario := os.Getenv("EASYNET_JSON_LAB_SCENARIO")
	if root == "" && scenario == "" {
		return
	}
	allowed := map[string]bool{"cas-Alpha": true, "cas-Beta": true, "migration-cas": true, "write-before": true, "write-after": true, "write-boundary": true, "migration-before": true, "migration-after": true, "migration-boundary": true}
	if !allowed[scenario] || !labRoot.MatchString(root) {
		t.Fatal("invalid child fixture scope")
	}
	events := os.NewFile(3, "owned-events")
	control := os.NewFile(4, "owned-control")
	defer events.Close()
	defer control.Close()
	reader := bufio.NewReader(control)
	signal := func(stage string) error {
		n, e := io.WriteString(events, stage+"\n")
		if e != nil || n != len(stage)+1 {
			return ErrIO
		}
		return nil
	}
	barrier := func(stage string) error {
		if e := signal(stage); e != nil {
			return e
		}
		line, e := reader.ReadSlice('\n')
		if e != nil || string(line) != "GO\n" {
			return ErrIO
		}
		return nil
	}
	s, e := OpenJSONFixture(root, ownedResolver())
	errCode(t, e, nil)
	defer s.Close()
	migration := strings.HasPrefix(scenario, "migration-")
	var current, next Snapshot
	if migration {
		current, e = s.InspectMigration()
		errCode(t, e, nil)
		equalSnapshot(t, current, migrationFixture())
		next, e = StageMigration(current, ownedResolver())
		errCode(t, e, nil)
	} else {
		current, e = s.Load()
		errCode(t, e, nil)
		equalSnapshot(t, current, emptyFixture())
		id := "Alpha"
		if scenario == "cas-Beta" {
			id = "Beta"
		}
		next = childCandidate(id)
	}
	if strings.Contains(scenario, "cas") {
		errCode(t, barrier("READY"), nil)
	} else if strings.HasSuffix(scenario, "after") {
		s.afterPublish = func() error { return barrier("AFTER") }
	} else {
		s.beforePublish = func() error { return barrier("BEFORE") }
	}
	var result Snapshot
	if migration {
		result, e = s.CommitMigration(current.Generation, next)
	} else {
		result, e = s.Commit(current.Generation, next)
	}
	switch e {
	case nil:
		equalSnapshot(t, result, next)
		errCode(t, signal("OK"), nil)
	case ErrConflict:
		resultCode(t, result, e, ErrConflict)
		errCode(t, signal("CONFLICT"), nil)
	default:
		t.Fatal("unexpected child commit code")
	}
}
func childOutcome(t *testing.T, c *ownedChild) string {
	t.Helper()
	type answer struct {
		s string
		e error
	}
	done := make(chan answer, 1)
	go func() { b, e := c.reader.ReadSlice('\n'); done <- answer{string(b), e} }()
	select {
	case a := <-done:
		if a.e != nil || (a.s != "OK\n" && a.s != "CONFLICT\n") {
			t.Fatal("invalid owned commit acknowledgement")
		}
		return strings.TrimSuffix(a.s, "\n")
	case <-time.After(2 * time.Second):
		c.events.Close()
		<-done
		t.Fatal("owned commit deadline")
	}
	return ""
}
func TestJSONRealTwoWriterCAS(t *testing.T) {
	for _, migration := range []bool{false, true} {
		t.Run(fmt.Sprintf("migration=%v", migration), func(t *testing.T) {
			l := newLab(t)
			old := emptyFixture()
			aScenario, bScenario := "cas-Alpha", "cas-Beta"
			if migration {
				old = migrationFixture()
				aScenario, bScenario = "migration-cas", "migration-cas"
			}
			l.seed(t, old)
			a, b := startOwnedChild(t, l, aScenario), startOwnedChild(t, l, bScenario)
			a.event(t, "READY")
			b.event(t, "READY")
			a.release(t)
			b.release(t)
			ao, bo := childOutcome(t, a), childOutcome(t, b)
			a.reap(t, true)
			b.reap(t, true)
			if !(ao == "OK" && bo == "CONFLICT" || ao == "CONFLICT" && bo == "OK") {
				t.Fatal("CAS did not have exactly one winner")
			}
			s := openLab(t, l, ownedResolver())
			want := childCandidate("Alpha")
			if ao != "OK" {
				want = childCandidate("Beta")
			}
			if migration {
				want, _ = StageMigration(old, ownedResolver())
			}
			purity(t, l, s, want, false)
		})
	}
}

var ownedStagePattern = regexp.MustCompile(`^\.stage-[0-9a-f]{32}$`)

// recoverOwnedCrashFixture runs only after all owned writers have been reaped.
// It records the owned artifact inventory, removes only recorded staging names,
// and returns one complete old/new snapshot. Ordinary store methods never repair.
func recoverOwnedCrashFixture(t *testing.T, l *ownedLab, old, next Snapshot) (Snapshot, string) {
	t.Helper()
	artifacts, e := l.cleanupStages()
	errCode(t, e, nil)
	s := openLab(t, l, ownedResolver())
	var got Snapshot
	if old.SchemaVersion == 0 {
		got, e = s.Load()
		if e == ErrMigrationRequired {
			got, e = s.InspectMigration()
		}
	} else {
		got, e = s.Load()
	}
	errCode(t, e, nil)
	if !logicalEqual(got, old) && !logicalEqual(got, next) {
		t.Fatal("crash exposed partial or extra generation")
	}
	// Physical baseline is frozen only AFTER explicit recovery; repeated reads
	// must leave its bytes/files/modes/generation unchanged.
	purity(t, l, s, got, got.SchemaVersion == 0)
	return got, strings.Join(artifacts, ",")
}
func TestJSONControlledCrashMatrix(t *testing.T) {
	for _, migration := range []bool{false, true} {
		for _, phase := range []string{"before", "after", "boundary"} {
			count := 2
			if phase == "boundary" {
				count = 3
			}
			for trial := 0; trial < count; trial++ {
				t.Run(fmt.Sprintf("migration=%v/%s/%d", migration, phase, trial), func(t *testing.T) {
					l := newLab(t)
					old, next := emptyFixture(), childCandidate("Alpha")
					prefix := "write-"
					if migration {
						old = migrationFixture()
						next, _ = StageMigration(old, ownedResolver())
						prefix = "migration-"
					}
					l.seed(t, old)
					c := startOwnedChild(t, l, prefix+phase)
					stage := "BEFORE"
					if phase == "after" {
						stage = "AFTER"
					}
					c.event(t, stage)
					if phase == "boundary" {
						// Release the beforePublish pause, then race an actual Kill against
						// rename/fsync/ack. This is distinct from deterministic hook deaths.
						c.release(t)
						if trial > 0 {
							time.Sleep(time.Duration(trial) * time.Millisecond)
						}
					}
					c.killAndReap(t)
					got, artifacts := recoverOwnedCrashFixture(t, l, old, next)
					if phase == "before" {
						equalSnapshot(t, got, old)
					}
					if phase == "after" {
						equalSnapshot(t, got, next)
					}
					t.Logf("owned crash phase=%s trial=%d schema=%d generation=%d artifacts=%s", phase, trial, got.SchemaVersion, got.Generation, artifacts)
				})
			}
		}
	}
}

func TestJSONEarlyFailureOrphanCleanup(t *testing.T) {
	l := newLab(t)
	l.seed(t, emptyFixture())
	c := startOwnedChild(t, l, "write-before")
	c.event(t, "BEFORE")
	// Calling cleanup while any child is live must refuse even a known stage.
	_, e := l.cleanupStages()
	errCode(t, e, ErrIO)
	c.killAndReap(t)
	// Simulate a Fatal path skipping recoverOwnedCrashFixture: cleanup itself
	// must discover the child's unrecorded stage only after explicit Kill/Wait.
	artifacts, e := l.cleanupStages()
	errCode(t, e, nil)
	if len(artifacts) != 1 || !l.names[artifacts[0]] {
		t.Fatal("orphan not recorded")
	}
	s := openLab(t, l, ownedResolver())
	purity(t, l, s, emptyFixture(), false)
}
func TestJSONOrphanCleanupPreservesUnsafeAndUnrelated(t *testing.T) {
	for _, kind := range []string{"mode", "symlink", "hardlink", "unrelated"} {
		t.Run(kind, func(t *testing.T) {
			l := newLab(t)
			l.seed(t, emptyFixture())
			stage := ".stage-" + strings.Repeat("a", 32)
			path := filepath.Join(l.dir, stage)
			errCode(t, os.WriteFile(path, []byte("owned-stage"), 0600), nil)
			switch kind {
			case "mode":
				errCode(t, os.Chmod(path, 0644), nil)
			case "symlink":
				errCode(t, os.Remove(path), nil)
				errCode(t, os.Symlink(lockName, path), nil)
			case "hardlink":
				errCode(t, os.Link(path, filepath.Join(l.dir, "unrelated")), nil)
			case "unrelated":
				errCode(t, os.WriteFile(filepath.Join(l.dir, "unrelated"), []byte("preserve"), 0600), nil)
			}
			before := fingerprint(t, l)
			_, e := l.cleanupStages()
			errCode(t, e, ErrLocationUnsafe)
			if fingerprint(t, l) != before || l.names[stage] {
				t.Fatal("unsafe cleanup changed or adopted entries")
			}
			// These test-created entries are explicitly removed by their creator after
			// preservation assertions; the refusing cleanup helper never adopts them.
			errCode(t, os.Remove(path), nil)
			if kind == "hardlink" || kind == "unrelated" {
				errCode(t, os.Remove(filepath.Join(l.dir, "unrelated")), nil)
			}
		})
	}
}
