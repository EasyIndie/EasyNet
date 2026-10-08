//go:build darwin || linux

package statelab

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"golang.org/x/sys/unix"
)

type exactResolver struct {
	targets  map[string]Target
	profiles map[string]Profile
	status   Resolution
}

func ownedResolver() *exactResolver {
	r := &exactResolver{targets: map[string]Target{}, profiles: map[string]Profile{}, status: Available}
	for _, id := range []string{"Alpha", "Beta"} {
		t := Target{id, 1, "cred_" + id}
		r.targets[t.CredentialRef] = t
	}
	for _, rev := range []uint32{1, 2} {
		p := Profile{"Profile", rev, "Alpha", "hysteria2-native", "hysteria2", "hysteria2-native-config", fmt.Sprintf("config_Profile%d", rev)}
		r.profiles[p.ConfigRef] = p
	}
	return r
}
func (r *exactResolver) ResolveCredential(t Target) Resolution {
	if r.status != Available {
		return r.status
	}
	v, ok := r.targets[t.CredentialRef]
	if !ok {
		return Missing
	}
	if v != t {
		return Mismatch
	}
	return Available
}
func (r *exactResolver) ResolveConfig(p Profile) Resolution {
	if r.status != Available {
		return r.status
	}
	v, ok := r.profiles[p.ConfigRef]
	if !ok {
		return Missing
	}
	if v.TargetID != p.TargetID || v.RuntimeID != p.RuntimeID || v.ProtocolID != p.ProtocolID || v.Format != p.Format || v.Revision != p.Revision {
		return Mismatch
	}
	return Available
}
func emptyFixture() Snapshot { return Snapshot{SchemaVersion: 1} }
func addition(id string) Snapshot {
	return Snapshot{SchemaVersion: 1, Generation: 1, Targets: []Target{{id, 1, "cred_" + id}}}
}
func migrationFixture() Snapshot {
	s := addition("Alpha")
	s.SchemaVersion = 0
	s.Generation = 7
	s.Profiles = []Profile{ownedResolver().profiles["config_Profile1"]}
	s.Operations = []Operation{{"Operation", "Alpha", "sha256:" + strings.Repeat("a", 64), "unknown"}}
	return s
}

func openLab(t *testing.T, l *ownedLab, r Resolver) *JSONStore {
	t.Helper()
	s, e := OpenJSONFixture(l.dir, r)
	errCode(t, e, nil)
	t.Cleanup(func() {
		if !s.closed {
			errCode(t, s.Close(), nil)
		}
	})
	return s
}
func errCode(t *testing.T, got error, want error) {
	t.Helper()
	if got != want {
		t.Fatalf("error code got %v want %v", got, want)
	}
	if got != nil {
		var ec ErrorCode
		if !errors.As(got, &ec) {
			t.Fatal("nonfixed error")
		}
	}
}
func resultCode(t *testing.T, got Snapshot, e, want error) {
	t.Helper()
	errCode(t, e, want)
	if e != nil && !reflect.DeepEqual(got, Snapshot{}) {
		t.Fatal("nonzero error result")
	}
}
func equalSnapshot(t *testing.T, got, want Snapshot) {
	t.Helper()
	if !logicalEqual(got, want) {
		t.Fatal("whole snapshot mismatch")
	}
}

// fingerprint intentionally excludes atime: reads may update it. Bytes, names,
// exact permissions and generation encoded in bytes are included.
func fingerprint(t *testing.T, l *ownedLab) string {
	t.Helper()
	entries, e := os.ReadDir(l.dir)
	if e != nil {
		t.Fatal("list failed")
	}
	var b strings.Builder
	rootInfo, e := os.Lstat(l.dir)
	if e != nil {
		t.Fatal("root stat failed")
	}
	fmt.Fprintf(&b, "root:%v\n", rootInfo.Mode())
	for _, entry := range entries {
		path := filepath.Join(l.dir, entry.Name())
		st, e := os.Lstat(path)
		if e != nil {
			t.Fatal("stat failed")
		}
		fmt.Fprintf(&b, "%s:%v:", entry.Name(), st.Mode())
		if st.Mode().IsRegular() {
			data, e := os.ReadFile(path)
			if e != nil {
				t.Fatal("read failed")
			}
			b.Write(data)
		}
		if st.Mode()&os.ModeSymlink != 0 {
			target, e := os.Readlink(path)
			if e != nil {
				t.Fatal("readlink failed")
			}
			b.WriteString(target)
		}
		b.WriteByte('\n')
	}
	return b.String()
}
func purity(t *testing.T, l *ownedLab, s *JSONStore, want Snapshot, migration bool) {
	t.Helper()
	baseline := fingerprint(t, l)
	for i := 0; i < 3; i++ {
		if migration {
			got, e := s.InspectMigration()
			errCode(t, e, nil)
			equalSnapshot(t, got, want)
		} else {
			got, e := s.Load()
			errCode(t, e, nil)
			equalSnapshot(t, got, want)
			got, e = s.Snapshot()
			errCode(t, e, nil)
			equalSnapshot(t, got, want)
		}
		if fingerprint(t, l) != baseline {
			t.Fatal("read mutated physical baseline")
		}
	}
}
func TestJSONCRUDPurityAndClose(t *testing.T) {
	l := newLab(t)
	l.seed(t, emptyFixture())
	s := openLab(t, l, ownedResolver())
	purity(t, l, s, emptyFixture(), false)
	next := addition("Alpha")
	next.Profiles = []Profile{ownedResolver().profiles["config_Profile1"]}
	got, e := s.Commit(0, next)
	errCode(t, e, nil)
	equalSnapshot(t, got, next)
	next.Generation = 2
	next.Profiles[0] = ownedResolver().profiles["config_Profile2"]
	got, e = s.Commit(1, next)
	errCode(t, e, nil)
	equalSnapshot(t, got, next)
	// Returned copies cannot mutate the persisted snapshot.
	got.Targets[0].ID = "Beta"
	purity(t, l, s, next, false)
	next.Generation = 3
	next.Profiles = nil
	got, e = s.Commit(2, next)
	errCode(t, e, nil)
	equalSnapshot(t, got, next)
	next.Generation = 4
	next.Targets = nil
	got, e = s.Commit(3, next)
	errCode(t, e, nil)
	purity(t, l, s, next, false)
	resultCode(t, got, nil, nil)
	errCode(t, s.Close(), nil)
	got, e = s.Load()
	resultCode(t, got, e, ErrIO)
	errCode(t, s.Close(), ErrIO)
}
func TestJSONCommitRejections(t *testing.T) {
	tests := []struct {
		name     string
		modify   func(*Snapshot, *exactResolver)
		expected uint32
		code     error
	}{
		{"invalid shape", func(s *Snapshot, r *exactResolver) { s.Targets[0].ID = "1bad" }, 0, ErrInvalid},
		{"missing credential", func(s *Snapshot, r *exactResolver) { s.Targets[0].CredentialRef = "cred_absent" }, 0, ErrUnresolved},
		{"locked", func(s *Snapshot, r *exactResolver) { r.status = Locked }, 0, ErrSecretLocked},
		{"mismatch", func(s *Snapshot, r *exactResolver) { s.Targets[0].Revision = 2 }, 0, ErrRefMismatch},
		{"missing target", func(s *Snapshot, r *exactResolver) {
			s.Profiles = []Profile{r.profiles["config_Profile1"]}
			s.Targets = nil
		}, 0, ErrUnresolved},
		{"missing config", func(s *Snapshot, r *exactResolver) {
			s.Profiles = []Profile{r.profiles["config_Profile1"]}
			s.Profiles[0].ConfigRef = "config_absent"
		}, 0, ErrUnresolved},
		{"config binding", func(s *Snapshot, r *exactResolver) {
			s.Profiles = []Profile{r.profiles["config_Profile1"]}
			s.Profiles[0].Revision = 2
		}, 0, ErrRefMismatch},
		{"successor", func(s *Snapshot, r *exactResolver) { s.Generation = 2 }, 0, ErrInvalid},
		{"stale", func(s *Snapshot, r *exactResolver) { s.Generation = 2 }, 1, ErrConflict},
		{"expected overflow", func(s *Snapshot, r *exactResolver) {}, MaxGeneration + 1, ErrInvalid},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			l := newLab(t)
			l.seed(t, emptyFixture())
			r := ownedResolver()
			s := openLab(t, l, r)
			next := addition("Alpha")
			tc.modify(&next, r)
			before := fingerprint(t, l)
			got, e := s.Commit(tc.expected, next)
			resultCode(t, got, e, tc.code)
			if fingerprint(t, l) != before {
				t.Fatal("rejection mutated state")
			}
		})
	}
	t.Run("exhausted", func(t *testing.T) {
		l := newLab(t)
		seed := emptyFixture()
		seed.Generation = MaxGeneration
		l.seed(t, seed)
		s := openLab(t, l, nil)
		before := fingerprint(t, l)
		got, e := s.Commit(MaxGeneration, Snapshot{})
		resultCode(t, got, e, ErrExhausted)
		if fingerprint(t, l) != before {
			t.Fatal("exhausted changed state")
		}
	})
}
func TestJSONStrictReadPreserves(t *testing.T) {
	base, _ := EncodeFixture(emptyFixture(), nil)
	cases := []struct {
		name string
		raw  []byte
		code error
	}{
		{"malformed", []byte("{"), ErrCorrupt},
		{"future", bytes.Replace(base, []byte(`"schemaVersion":1`), []byte(`"schemaVersion":2`), 1), ErrUnsupported},
		{"duplicate", bytes.Replace(base, []byte(`"generation":0`), []byte(`"generation":0,"generation":0`), 1), ErrInvalid},
		{"unknown", bytes.Replace(base, []byte(`"generation":0`), []byte(`"extra":0,"generation":0`), 1), ErrInvalid},
		{"null", bytes.Replace(base, []byte(`"targets":[]`), []byte(`"targets":null`), 1), ErrInvalid},
		{"missing", bytes.Replace(base, []byte(`"generation":0,`), nil, 1), ErrInvalid},
		{"numeric string", bytes.Replace(base, []byte(`"generation":0`), []byte(`"generation":"0"`), 1), ErrInvalid},
		{"bound", bytes.Replace(base, []byte(`"generation":0`), []byte(`"generation":2147483648`), 1), ErrInvalid},
		{"lexical", bytes.Replace(base, []byte(`"generation":0`), []byte(`"generation":0e0`), 1), ErrInvalid},
		{"oversize", bytes.Repeat([]byte(" "), maxFixture+1), ErrInvalid},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			l := newLab(t)
			l.seed(t, emptyFixture())
			errCode(t, os.WriteFile(filepath.Join(l.dir, stateName), tc.raw, 0600), nil)
			baseline := fingerprint(t, l)
			s := openLab(t, l, nil)
			got, e := s.Load()
			resultCode(t, got, e, tc.code)
			got, e = s.Snapshot()
			resultCode(t, got, e, tc.code)
			got, e = s.Commit(0, addition("Alpha"))
			resultCode(t, got, e, tc.code)
			if fingerprint(t, l) != baseline {
				t.Fatal("normal read repaired invalid state")
			}
		})
	}
}
func TestJSONPublicationFaults(t *testing.T) {
	for _, migration := range []bool{false, true} {
		for _, phase := range []string{"before", "after", "ack"} {
			t.Run(fmt.Sprintf("migration=%v/%s", migration, phase), func(t *testing.T) {
				l := newLab(t)
				old := emptyFixture()
				next := addition("Alpha")
				if migration {
					old = migrationFixture()
					next, _ = StageMigration(old, ownedResolver())
				}
				l.seed(t, old)
				s := openLab(t, l, ownedResolver())
				fault := func() error { return ErrIO }
				switch phase {
				case "before":
					s.beforePublish = fault
				case "after":
					s.afterPublish = fault
				case "ack":
					s.beforeAck = fault
				}
				var got Snapshot
				var e error
				if migration {
					got, e = s.CommitMigration(old.Generation, next)
				} else {
					got, e = s.Commit(old.Generation, next)
				}
				want := ErrCommitUnknown
				if phase == "before" {
					want = ErrIO
				}
				resultCode(t, got, e, want)
				if phase == "before" {
					purity(t, l, s, old, migration)
				} else {
					purity(t, l, s, next, false)
				}
			})
		}
	}
}
func TestJSONMigrationAndMirror(t *testing.T) {
	l := newLab(t)
	old := migrationFixture()
	l.seed(t, old)
	r := ownedResolver()
	s := openLab(t, l, r)
	got, e := s.Load()
	resultCode(t, got, e, ErrMigrationRequired)
	purity(t, l, s, old, true)
	next, e := StageMigration(old, r)
	errCode(t, e, nil)
	// Whole logical equality permits reordered arrays, but not changed records.
	got, e = s.CommitMigration(old.Generation, next)
	errCode(t, e, nil)
	equalSnapshot(t, got, next)
	got, e = s.CommitMigration(old.Generation, next)
	resultCode(t, got, e, ErrConflict)
	got, e = s.InspectMigration()
	resultCode(t, got, e, ErrInvalid)
	for _, kind := range []string{"remove", "retarget", "rehash"} {
		t.Run(kind, func(t *testing.T) {
			candidate := clone(next)
			candidate.Generation++
			switch kind {
			case "remove":
				candidate.Operations = nil
			case "retarget":
				candidate.Targets = append(candidate.Targets, r.targets["cred_Beta"])
				candidate.Operations[0].TargetID = "Beta"
			case "rehash":
				candidate.Operations[0].PlanHash = "sha256:" + strings.Repeat("b", 64)
			}
			before := fingerprint(t, l)
			got, e := s.Commit(next.Generation, candidate)
			resultCode(t, got, e, ErrBindingImmutable)
			if fingerprint(t, l) != before {
				t.Fatal("mirror changed")
			}
		})
	}
	purity(t, l, s, next, false)
}
func TestJSONMigrationRejections(t *testing.T) {
	for _, status := range []Resolution{Missing, Locked, Mismatch} {
		t.Run(fmt.Sprint(status), func(t *testing.T) {
			l := newLab(t)
			old := migrationFixture()
			l.seed(t, old)
			r := ownedResolver()
			next, _ := StageMigration(old, r)
			r.status = status
			s := openLab(t, l, r)
			want := map[Resolution]ErrorCode{Missing: ErrUnresolved, Locked: ErrSecretLocked, Mismatch: ErrRefMismatch}[status]
			before := fingerprint(t, l)
			got, e := s.InspectMigration()
			resultCode(t, got, e, want)
			got, e = s.CommitMigration(old.Generation, next)
			resultCode(t, got, e, want)
			if fingerprint(t, l) != before {
				t.Fatal("migration rejection changed state")
			}
		})
	}
	t.Run("staged changed", func(t *testing.T) {
		l := newLab(t)
		old := migrationFixture()
		l.seed(t, old)
		s := openLab(t, l, ownedResolver())
		next, _ := StageMigration(old, ownedResolver())
		next.Operations = nil
		before := fingerprint(t, l)
		got, e := s.CommitMigration(old.Generation, next)
		resultCode(t, got, e, ErrInvalid)
		if fingerprint(t, l) != before {
			t.Fatal("staged fault changed state")
		}
	})
}
func TestJSONGuards(t *testing.T) {
	for _, path := range []string{"relative", "/tmp/../tmp/easynet-state-lab-bad", "/tmp/not-owned", "/Users/example/private", "/private/tmp/easynet-state-lab-"} {
		t.Run("outside "+path, func(t *testing.T) {
			_, e := OpenJSONFixture(path, nil)
			errCode(t, e, ErrLocationUnsafe)
			errCode(t, SeedJSONFixture(path, emptyFixture(), nil), ErrLocationUnsafe)
		})
	}
	t.Run("pure UID", func(t *testing.T) {
		st := unix.Stat_t{Uid: uint32(os.Geteuid() + 1), Mode: unix.S_IFREG | 0600, Nlink: 1}
		if safeStat(&st, false, uint32(os.Geteuid())) {
			t.Fatal("wrong UID accepted")
		}
	})
	t.Run("missing and seed nonempty", func(t *testing.T) {
		l := newLab(t)
		_, e := OpenJSONFixture(l.dir, nil)
		errCode(t, e, ErrNotFound)
		l.names["owned-extra"] = true
		errCode(t, os.WriteFile(filepath.Join(l.dir, "owned-extra"), []byte("fixture"), 0600), nil)
		before := fingerprint(t, l)
		errCode(t, SeedJSONFixture(l.dir, emptyFixture(), nil), ErrLocationUnsafe)
		if fingerprint(t, l) != before {
			t.Fatal("nonempty seed changed files")
		}
	})
	for _, kind := range []string{"rootmode", "filemode", "lockmode", "symlink", "hardlink", "fifo", "directory", "lockreplace"} {
		t.Run(kind, func(t *testing.T) {
			l := newLab(t)
			l.seed(t, emptyFixture())
			var held *JSONStore
			if kind == "lockreplace" {
				held = openLab(t, l, nil)
			}
			path := filepath.Join(l.dir, stateName)
			switch kind {
			case "rootmode":
				errCode(t, unix.Fchmod(l.root, 0755), nil)
			case "filemode":
				errCode(t, os.Chmod(path, 0644), nil)
			case "lockmode":
				errCode(t, os.Chmod(filepath.Join(l.dir, lockName), 0644), nil)
			case "symlink":
				errCode(t, os.Remove(path), nil)
				errCode(t, os.Symlink(lockName, path), nil)
			case "hardlink":
				l.names["owned-link"] = true
				errCode(t, os.Link(path, filepath.Join(l.dir, "owned-link")), nil)
			case "fifo":
				errCode(t, os.Remove(path), nil)
				errCode(t, unix.Mkfifo(path, 0600), nil)
			case "directory":
				errCode(t, os.Remove(path), nil)
				errCode(t, os.Mkdir(path, 0600), nil)
			case "lockreplace":
				errCode(t, os.Remove(filepath.Join(l.dir, lockName)), nil)
				errCode(t, os.WriteFile(filepath.Join(l.dir, lockName), nil, 0600), nil)
			}
			before := fingerprint(t, l)
			if held != nil {
				got, e := held.Load()
				resultCode(t, got, e, ErrLocationUnsafe)
			} else {
				_, e := OpenJSONFixture(l.dir, nil)
				errCode(t, e, ErrLocationUnsafe)
			}
			if fingerprint(t, l) != before {
				t.Fatal("unsafe entry repaired")
			}
			if kind == "rootmode" {
				// Explicit creator-owned fixture teardown AFTER assertions; the backend
				// never restores unsafe modes. Use the original FD, not a followed path.
				errCode(t, unix.Fchmod(l.root, 0700), nil)
			}
		})
	}
	t.Run("root symlink", func(t *testing.T) {
		l := newLab(t)
		other := newLab(t)
		errCode(t, os.Remove(l.dir), nil)
		errCode(t, os.Symlink(other.dir, l.dir), nil)
		_, e := OpenJSONFixture(l.dir, nil)
		errCode(t, e, ErrLocationUnsafe)
	})
}
func TestJSONPostFlockRevalidation(t *testing.T) {
	l := newLab(t)
	l.seed(t, emptyFixture())
	s := openLab(t, l, nil)
	errCode(t, s.guard(), nil)
	errCode(t, unix.Flock(s.lock, unix.LOCK_EX), nil)
	defer unix.Flock(s.lock, unix.LOCK_UN)
	// Deterministic helper evidence: replace the named inode only AFTER a real
	// successful flock, then require the post-acquisition guard to reject it.
	// Source review separately verifies acquire invokes this guard after flock.
	errCode(t, os.Remove(filepath.Join(l.dir, lockName)), nil)
	errCode(t, os.WriteFile(filepath.Join(l.dir, lockName), nil, 0600), nil)
	before := fingerprint(t, l)
	errCode(t, s.guard(), ErrLocationUnsafe)
	if fingerprint(t, l) != before {
		t.Fatal("post-flock guard changed fixture")
	}
}

func TestJSONCanonicalMigrationOrdering(t *testing.T) {
	l := newLab(t)
	old := migrationFixture()
	old.Targets = append(old.Targets, ownedResolver().targets["cred_Beta"])
	l.seed(t, old)
	next, e := StageMigration(old, ownedResolver())
	errCode(t, e, nil)
	next.Targets[0], next.Targets[1] = next.Targets[1], next.Targets[0]
	s := openLab(t, l, ownedResolver())
	got, e := s.CommitMigration(old.Generation, next)
	errCode(t, e, nil)
	equalSnapshot(t, got, next)
	raw, e := os.ReadFile(filepath.Join(l.dir, stateName))
	errCode(t, e, nil)
	canonical, e := EncodeFixture(next, ownedResolver())
	errCode(t, e, nil)
	if !bytes.Equal(raw, canonical) {
		t.Fatal("migration not canonical")
	}
	purity(t, l, s, next, false)
}
func TestJSONAbsentFilesReadAndLockDeadline(t *testing.T) {
	for _, name := range []string{stateName, lockName} {
		t.Run(name, func(t *testing.T) {
			l := newLab(t)
			l.seed(t, emptyFixture())
			errCode(t, os.Remove(filepath.Join(l.dir, name)), nil)
			before := fingerprint(t, l)
			_, e := OpenJSONFixture(l.dir, nil)
			errCode(t, e, ErrNotFound)
			if before != fingerprint(t, l) {
				t.Fatal("absent file recreated")
			}
		})
	}
	t.Run("absent root", func(t *testing.T) {
		l := newLab(t)
		errCode(t, os.Remove(l.dir), nil)
		_, e := OpenJSONFixture(l.dir, nil)
		errCode(t, e, ErrNotFound)
		errCode(t, os.Mkdir(l.dir, 0700), nil)
	})
	t.Run("lock deadline", func(t *testing.T) {
		l := newLab(t)
		l.seed(t, emptyFixture())
		s := openLab(t, l, nil)
		blocker, e := guardedFile(s.root, lockName, unix.O_RDWR)
		errCode(t, e, nil)
		defer unix.Close(blocker)
		errCode(t, unix.Flock(blocker, unix.LOCK_EX), nil)
		defer unix.Flock(blocker, unix.LOCK_UN)
		before := fingerprint(t, l)
		start := time.Now()
		got, e := s.Load()
		resultCode(t, got, e, ErrIO)
		if time.Since(start) > 3*time.Second {
			t.Fatal("lock wait unbounded")
		}
		if fingerprint(t, l) != before {
			t.Fatal("lock timeout mutated fixture")
		}
	})
}
func TestJSONMirrorInsertionAndInvalidRevision(t *testing.T) {
	l := newLab(t)
	l.seed(t, emptyFixture())
	r := ownedResolver()
	s := openLab(t, l, r)
	next := childCandidate("Alpha")
	got, e := s.Commit(0, next)
	errCode(t, e, nil)
	equalSnapshot(t, got, next)
	errCode(t, s.Close(), nil)
	s = openLab(t, l, r)
	purity(t, l, s, next, false)
	candidate := clone(next)
	candidate.Generation++
	candidate.Targets[0].Revision = 3
	candidate.Targets[0].CredentialRef = "cred_Alpha3"
	r.targets["cred_Alpha3"] = candidate.Targets[0]
	before := fingerprint(t, l)
	got, e = s.Commit(next.Generation, candidate)
	resultCode(t, got, e, ErrInvalid)
	if fingerprint(t, l) != before {
		t.Fatal("revision skip mutated state")
	}
}

func TestJSONConfigBindingIndependentOfProfileID(t *testing.T) {
	l := newLab(t)
	l.seed(t, emptyFixture())
	r := ownedResolver()
	s := openLab(t, l, r)
	next := addition("Alpha")
	profile := r.profiles["config_Profile1"]
	profile.ID = "DifferentProfile"
	next.Profiles = []Profile{profile}
	got, e := s.Commit(0, next)
	errCode(t, e, nil)
	equalSnapshot(t, got, next)
	purity(t, l, s, next, false)
}
