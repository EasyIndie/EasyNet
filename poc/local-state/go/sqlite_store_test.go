//go:build darwin && cgo

package statelab

import (
	"bytes"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"golang.org/x/sys/unix"
)

func TestSQLiteNativeFacts(t *testing.T) {
	version, source := sqliteVersion()
	if version == "" || source == "" || len(version) > 64 || len(source) > 256 {
		t.Fatal("linked native version")
	}
	t.Logf("linked SQLite=%s source-id=%s", version, source)
	t.Logf("linked OMIT_LOAD_EXTENSION=%t", sqliteExtensionOmitted())
	l := newSQLiteLab(t)
	l.preserve = true // Preserve diagnostic seed failure; cleanup still closes descriptors.
	errCode(t, seedSQLiteFixture(l.dir, emptyFixture(), ownedResolver(), func(stage, code, actual int) {
		t.Logf("native diagnostic stage=%d code=%d actual=%d", stage, code, actual)
	}), nil)
	l.seeded = true
	l.preserve = false
	s := openSQLiteLab(t, l, ownedResolver())
	errCode(t, s.locker.acquire(false), nil)
	defer unix.Flock(s.locker.lock, unix.LOCK_UN)
	fd, e := s.databaseFD(false, true)
	errCode(t, e, nil)
	defer unix.Close(fd)
	d, e := s.native(fd, true, false)
	errCode(t, e, nil)
	defer d.close()
	errCode(t, d.settings(false, false), nil)
	opts, e := d.rows("PRAGMA compile_options", 256)
	errCode(t, e, nil)
	for _, r := range opts {
		if len(r) != 1 || r[0].kind != sqlText || len(r[0].bytes) > 256 {
			t.Fatal("bounded options")
		}
		t.Logf("compile option=%s", r[0].bytes)
	}
	for _, query := range []string{"PRAGMA synchronous", "PRAGMA fullfsync", "PRAGMA temp_store"} {
		rows, e := d.rows(query, 1)
		errCode(t, e, nil)
		if len(rows) != 1 || len(rows[0]) != 1 || rows[0][0].kind != sqlInteger {
			t.Fatal("connection options")
		}
		t.Logf("readonly %s=%d", query, rows[0][0].number)
	}
	t.Log("RW verified DELETE page4096 synchronous3 fullfsync1 temp_store2 mmap0 NORMAL busy1000; defensive1 trusted0 DQS0 extensions0 SQL4096 value32768 attached0")
}
func TestSQLiteCRUDCopiesClose(t *testing.T) {
	l := newSQLiteLab(t)
	l.seed(t, emptyFixture())
	r := ownedResolver()
	s := openSQLiteLab(t, l, r)
	got, e := s.Load()
	resultCode(t, got, e, nil)
	equalSnapshot(t, got, emptyFixture())
	next := addition("Alpha")
	next.Profiles = []Profile{r.profiles["config_Profile1"]}
	got, e = s.Commit(0, next)
	resultCode(t, got, e, nil)
	equalSnapshot(t, got, next)
	next.Targets[0].ID = "Beta"
	got.Targets[0].ID = "Beta"
	persisted, e := s.Load()
	resultCode(t, persisted, e, nil)
	if persisted.Targets[0].ID != "Alpha" {
		t.Fatal("alias escaped")
	}
	next = clone(persisted)
	next.Generation = 2
	next.Profiles[0] = r.profiles["config_Profile2"]
	got, e = s.Commit(1, next)
	resultCode(t, got, e, nil)
	equalSnapshot(t, got, next)
	next.Generation = 3
	next.Profiles = nil
	got, e = s.Commit(2, next)
	resultCode(t, got, e, nil)
	equalSnapshot(t, got, next)
	next.Generation = 4
	next.Targets = nil
	got, e = s.Commit(3, next)
	resultCode(t, got, e, nil)
	equalSnapshot(t, got, next)
	sqlitePurity(t, l, next)
	errCode(t, s.Close(), nil)
	got, e = s.Load()
	resultCode(t, got, e, ErrIO)
	got, e = s.Commit(4, Snapshot{SchemaVersion: 1, Generation: 5})
	resultCode(t, got, e, ErrIO)
	errCode(t, s.Close(), ErrIO)
}
func TestSQLiteLogicalRefusals(t *testing.T) {
	cases := []struct {
		name   string
		mutate func(*Snapshot)
		want   error
	}{
		{"duplicate-id", func(s *Snapshot) { s.Targets = append(s.Targets, s.Targets[0]) }, ErrInvalid},
		{"zero-revision", func(s *Snapshot) { s.Targets[0].Revision = 0 }, ErrInvalid},
		{"bad-id", func(s *Snapshot) { s.Targets[0].ID = "Alpha\n" }, ErrInvalid},
		{"bound", func(s *Snapshot) { s.Targets = make([]Target, 5) }, ErrInvalid},
		{"bad-ref", func(s *Snapshot) { s.Targets[0].CredentialRef = "/secret" }, ErrInvalid},
		{"missing-credential", func(s *Snapshot) { s.Targets[0].CredentialRef = "cred_absent" }, ErrUnresolved},
		{"missing-target", func(s *Snapshot) {
			s.Profiles = []Profile{ownedResolver().profiles["config_Profile1"]}
			s.Targets = nil
		}, ErrUnresolved},
		{"missing-config", func(s *Snapshot) {
			s.Profiles = []Profile{ownedResolver().profiles["config_Profile1"]}
			s.Profiles[0].ConfigRef = "config_absent"
		}, ErrUnresolved},
		{"mismatched-config", func(s *Snapshot) {
			s.Profiles = []Profile{ownedResolver().profiles["config_Profile1"]}
			s.Profiles[0].ConfigRef = "config_Profile2"
		}, ErrRefMismatch},
		{"future-candidate", func(s *Snapshot) { s.SchemaVersion = 2 }, ErrUnsupported},
		{"generation", func(s *Snapshot) { s.Generation = 2 }, ErrInvalid},
		{"tuple", func(s *Snapshot) {
			s.Profiles = []Profile{ownedResolver().profiles["config_Profile1"]}
			s.Profiles[0].RuntimeID = "wireguard"
		}, ErrInvalid},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			l := newSQLiteLab(t)
			l.seed(t, emptyFixture())
			s := openSQLiteLab(t, l, ownedResolver())
			baseline := sqliteFingerprint(t, l)
			next := addition("Alpha")
			tc.mutate(&next)
			got, e := s.Commit(0, next)
			resultCode(t, got, e, tc.want)
			if sqliteFingerprint(t, l) != baseline {
				t.Fatal("refusal changed fixture")
			}
		})
	}
	for _, status := range []Resolution{Missing, Locked, Mismatch} {
		t.Run(fmt.Sprint("resolver-", status), func(t *testing.T) {
			l := newSQLiteLab(t)
			l.seed(t, addition("Alpha"))
			r := ownedResolver()
			r.status = status
			s := openSQLiteLab(t, l, r)
			want := error(ErrUnresolved)
			if status == Locked {
				want = ErrSecretLocked
			}
			if status == Mismatch {
				want = ErrRefMismatch
			}
			baseline := sqliteFingerprint(t, l)
			got, e := s.Load()
			resultCode(t, got, e, want)
			next := addition("Alpha")
			next.Generation = 2
			got, e = s.Commit(1, next)
			resultCode(t, got, e, want)
			if sqliteFingerprint(t, l) != baseline {
				t.Fatal("resolver refusal changed state")
			}
		})
	}
}

// The creator alone uses fixed selectors to construct invalid physical fixtures.
func sqliteCreatorMutation(t *testing.T, l *sqliteLab, selector string, payload []byte) {
	t.Helper()
	s := openSQLiteLab(t, l, ownedResolver())
	errCode(t, s.locker.acquire(true), nil)
	defer unix.Flock(s.locker.lock, unix.LOCK_UN)
	fd, e := s.databaseFD(false, true)
	errCode(t, e, nil)
	defer unix.Close(fd)
	d, e := s.native(fd, false, false)
	errCode(t, e, nil)
	defer d.close()
	errCode(t, d.settings(true, false), nil)
	switch selector {
	case "payload":
		errCode(t, d.exec("UPDATE state_snapshot SET payload=?1", nil, payload), nil)
	case "future":
		errCode(t, d.exec("UPDATE state_snapshot SET schema_version=2,payload=?1", nil, payload), nil)
	case "header-mismatch":
		errCode(t, d.exec("UPDATE state_snapshot SET schema_version=0", nil, nil), nil)
	case "missing-row":
		errCode(t, d.exec("DELETE FROM state_snapshot", nil, nil), nil)
	case "extra-table":
		errCode(t, d.exec("CREATE TABLE extra(value ANY) STRICT", nil, nil), nil)
	case "extra-view":
		errCode(t, d.exec("CREATE VIEW extra AS SELECT 1", nil, nil), nil)
	case "extra-index":
		errCode(t, d.exec("CREATE INDEX extra ON state_snapshot(generation)", nil, nil), nil)
	case "extra-trigger":
		errCode(t, d.exec("CREATE TRIGGER extra AFTER UPDATE ON state_snapshot BEGIN SELECT 1; END", nil, nil), nil)
	case "wrong-type", "constraint":
		errCode(t, d.exec("PRAGMA ignore_check_constraints=ON", nil, nil), nil)
		sql := "UPDATE state_snapshot SET generation='0'"
		if selector == "constraint" {
			sql = "UPDATE state_snapshot SET singleton=2"
		}
		errCode(t, d.exec(sql, nil, nil), nil)
	case "wrong-ddl":
		errCode(t, d.exec("DROP TABLE state_snapshot", nil, nil), nil)
		errCode(t, d.exec("CREATE TABLE state_snapshot(singleton INTEGER PRIMARY KEY,schema_version INTEGER,generation INTEGER,payload BLOB)", nil, nil), nil)
	default:
		t.Fatal("creator selector")
	}
}
func TestSQLiteEncodingPhysicalNegatives(t *testing.T) {
	canonical := `{"schemaVersion":1,"generation":0,"targets":[],"profiles":[],"operations":[]}`
	cases := []struct {
		name, selector, payload string
		want                    error
	}{
		{"duplicate-key", "payload", strings.Replace(canonical, `"generation":0`, `"generation":0,"generation":0`, 1), ErrInvalid},
		{"unknown", "payload", strings.Replace(canonical, `"generation":0`, `"generation":0,"extra":0`, 1), ErrInvalid},
		{"missing", "payload", strings.Replace(canonical, `"generation":0,`, "", 1), ErrInvalid},
		{"null", "payload", strings.Replace(canonical, `"targets":[]`, `"targets":null`, 1), ErrInvalid},
		{"float", "payload", strings.Replace(canonical, `"generation":0`, `"generation":0.0`, 1), ErrInvalid},
		{"exponent", "payload", strings.Replace(canonical, `"generation":0`, `"generation":0e0`, 1), ErrInvalid},
		{"signed", "payload", strings.Replace(canonical, `"generation":0`, `"generation":-0`, 1), ErrInvalid},
		{"string", "payload", strings.Replace(canonical, `"generation":0`, `"generation":"0"`, 1), ErrInvalid},
		{"bool", "payload", strings.Replace(canonical, `"generation":0`, `"generation":false`, 1), ErrInvalid},
		{"overflow", "payload", strings.Replace(canonical, `"generation":0`, `"generation":2147483648`, 1), ErrInvalid},
		{"trailing", "payload", canonical + " {}", ErrInvalid},
		{"malformed", "payload", "{", ErrCorrupt},
		{"utf8", "payload", string([]byte{255}), ErrCorrupt},
		{"future", "future", strings.Replace(canonical, `"schemaVersion":1`, `"schemaVersion":2`, 1), ErrUnsupported},
		{"header-mismatch", "header-mismatch", "", ErrCorrupt},
		{"missing-row", "missing-row", "", ErrInvalid},
		{"extra-table", "extra-table", "", ErrInvalid},
		{"extra-index", "extra-index", "", ErrInvalid},
		{"extra-view", "extra-view", "", ErrInvalid},
		{"extra-trigger", "extra-trigger", "", ErrInvalid},
		{"wrong-type", "wrong-type", "", ErrInvalid},
		{"constraint", "constraint", "", ErrInvalid},
		{"wrong-ddl", "wrong-ddl", "", ErrInvalid},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			l := newSQLiteLab(t)
			l.seed(t, emptyFixture())
			sqliteCreatorMutation(t, l, tc.selector, []byte(tc.payload))
			s := openSQLiteLab(t, l, ownedResolver())
			baseline := sqliteFingerprint(t, l)
			got, e := s.Load()
			resultCode(t, got, e, tc.want)
			got, e = s.Commit(0, addition("Alpha"))
			resultCode(t, got, e, tc.want)
			if sqliteFingerprint(t, l) != baseline {
				t.Fatal("diagnosis changed fixture")
			}
		})
	}
	for _, offset := range []int64{0, 16, 18, 19} {
		t.Run(fmt.Sprintf("physical-header-%d", offset), func(t *testing.T) {
			l := newSQLiteLab(t)
			l.seed(t, emptyFixture())
			fd, e := guardedFile(l.root, sqliteName, unix.O_RDWR)
			errCode(t, e, nil)
			if _, e := unix.Pwrite(fd, []byte{0}, offset); e != nil {
				t.Fatal("header mutation")
			}
			unix.Close(fd)
			baseline := sqliteFingerprint(t, l)
			s, e := OpenSQLiteFixture(l.dir, ownedResolver())
			if s != nil {
				s.Close()
				t.Fatal("corrupt open succeeded")
			}
			errCode(t, e, ErrCorrupt)
			if sqliteFingerprint(t, l) != baseline {
				t.Fatal("corrupt open changed fixture")
			}
		})
	}
}
func TestSQLiteMigrationImmutableExhaustion(t *testing.T) {
	l := newSQLiteLab(t)
	old := migrationFixture()
	l.seed(t, old)
	s := openSQLiteLab(t, l, ownedResolver())
	baseline := sqliteFingerprint(t, l)
	got, e := s.Load()
	resultCode(t, got, e, ErrMigrationRequired)
	got, e = s.Commit(old.Generation, addition("Alpha"))
	resultCode(t, got, e, ErrMigrationRequired)
	if sqliteFingerprint(t, l) != baseline {
		t.Fatal("ordinary v0 changed")
	}
	got, e = s.InspectMigration()
	resultCode(t, got, e, nil)
	equalSnapshot(t, got, old)
	next, e := StageMigration(got, ownedResolver())
	errCode(t, e, nil)
	invalid := clone(next)
	invalid.Generation++
	got, e = s.CommitMigration(old.Generation, invalid)
	resultCode(t, got, e, ErrInvalid)
	got, e = s.CommitMigration(old.Generation-1, next)
	resultCode(t, got, e, ErrConflict)
	got, e = s.CommitMigration(old.Generation, next)
	resultCode(t, got, e, nil)
	equalSnapshot(t, got, next)
	got, e = s.CommitMigration(old.Generation, next)
	resultCode(t, got, e, ErrConflict)
	for _, change := range []string{"remove", "retarget", "rehash"} {
		candidate := clone(next)
		candidate.Generation++
		switch change {
		case "remove":
			candidate.Operations = nil
		case "retarget":
			candidate.Targets = append(candidate.Targets, ownedResolver().targets["cred_Beta"])
			candidate.Operations[0].TargetID = "Beta"
		case "rehash":
			candidate.Operations[0].PlanHash = "sha256:" + strings.Repeat("b", 64)
		}
		before := sqliteFingerprint(t, l)
		got, e = s.Commit(next.Generation, candidate)
		resultCode(t, got, e, ErrBindingImmutable)
		if sqliteFingerprint(t, l) != before {
			t.Fatal("immutable changed")
		}
	}
	for _, version := range []uint32{0, 1} {
		t.Run(fmt.Sprint("exhausted-", version), func(t *testing.T) {
			l := newSQLiteLab(t)
			old := Snapshot{SchemaVersion: version, Generation: MaxGeneration}
			l.seed(t, old)
			s := openSQLiteLab(t, l, ownedResolver())
			baseline := sqliteFingerprint(t, l)
			if version == 0 {
				got, e = s.CommitMigration(MaxGeneration, Snapshot{})
				resultCode(t, got, e, ErrExhausted)
			} else {
				got, e = s.Commit(MaxGeneration, Snapshot{})
				resultCode(t, got, e, ErrExhausted)
			}
			if sqliteFingerprint(t, l) != baseline {
				t.Fatal("exhaustion changed fixture")
			}
		})
	}
}
func TestSQLiteMigrationReferenceRefusals(t *testing.T) {
	for _, status := range []Resolution{Missing, Locked, Mismatch} {
		t.Run(fmt.Sprint("v0-resolver-", status), func(t *testing.T) {
			l := newSQLiteLab(t)
			old := migrationFixture()
			l.seed(t, old)
			next, e := StageMigration(old, ownedResolver())
			errCode(t, e, nil)
			r := ownedResolver()
			r.status = status
			s := openSQLiteLab(t, l, r)
			want := error(ErrUnresolved)
			if status == Locked {
				want = ErrSecretLocked
			}
			if status == Mismatch {
				want = ErrRefMismatch
			}
			baseline := sqliteFingerprint(t, l)
			got, e := s.InspectMigration()
			resultCode(t, got, e, want)
			if sqliteFingerprint(t, l) != baseline {
				t.Fatal("v0 inspection refusal changed fixture")
			}
			got, e = s.CommitMigration(old.Generation, next)
			resultCode(t, got, e, want)
			if sqliteFingerprint(t, l) != baseline {
				t.Fatal("v0 migration refusal changed fixture")
			}
		})
	}
}

func TestSQLitePublicationFaults(t *testing.T) {
	for _, migration := range []bool{false, true} {
		for _, point := range []string{"before", "after", "ack"} {
			t.Run(fmt.Sprintf("migration-%t-%s", migration, point), func(t *testing.T) {
				l := newSQLiteLab(t)
				old := emptyFixture()
				next := addition("Alpha")
				if migration {
					old = migrationFixture()
					var e error
					next, e = StageMigration(old, ownedResolver())
					errCode(t, e, nil)
				}
				l.seed(t, old)
				s := openSQLiteLab(t, l, ownedResolver())
				wantErr := error(ErrCommitUnknown)
				want := next
				switch point {
				case "before":
					s.beforePublish = func(*sqliteDB) error { return ErrIO }
					wantErr = ErrIO
					want = old
				case "after":
					s.afterPublish = func() error { return ErrIO }
				case "ack":
					s.beforeAck = func() error { return ErrIO }
				}
				var got Snapshot
				var e error
				if migration {
					got, e = s.CommitMigration(old.Generation, next)
				} else {
					got, e = s.Commit(old.Generation, next)
				}
				resultCode(t, got, e, wantErr)
				sqlitePurity(t, l, want)
			})
		}
	}
}
func TestSQLiteUnsafeLocations(t *testing.T) {
	for _, path := range []string{".", "/tmp", "/tmp/easynet-state-lab-A/../B", "/Users/example/state"} {
		s, e := OpenSQLiteFixture(path, ownedResolver())
		if s != nil {
			s.Close()
			t.Fatal("outside root")
		}
		errCode(t, e, ErrLocationUnsafe)
	}
	var fake unix.Stat_t
	fake.Mode = unix.S_IFREG | 0600
	fake.Nlink = 1
	fake.Uid = uint32(os.Geteuid()) + 1
	if safeStat(&fake, false, uint32(os.Geteuid())) {
		t.Fatal("wrong UID stat guard")
	}
	for _, name := range []string{sqliteName, lockName, sqliteJournal, "state.sqlite-wal", "state.sqlite-shm", "unknown"} {
		for _, kind := range []string{"mode", "symlink", "hardlink"} {
			if name != "state.sqlite" && name != "state.lock" && kind != "mode" {
				continue
			}
			t.Run(name+"-"+kind, func(t *testing.T) {
				l := newSQLiteLab(t)
				l.seed(t, emptyFixture())
				s := openSQLiteLab(t, l, ownedResolver())
				path := l.dir + "/" + name
				if name != sqliteName && name != lockName {
					if e := os.WriteFile(path, []byte("owned"), 0600); e != nil {
						t.Fatal("aux setup")
					}
				}
				var original []byte
				switch kind {
				case "mode":
					if e := os.Chmod(path, 0644); e != nil {
						t.Fatal("mode fixture")
					}
				case "symlink":
					var e error
					original, e = os.ReadFile(path)
					if e != nil {
						t.Fatal("creator read")
					}
					if os.Remove(path) != nil || os.Symlink("missing", path) != nil {
						t.Fatal("symlink fixture")
					}
				case "hardlink":
					if os.Link(path, l.dir+"/owned-link") != nil {
						t.Fatal("hardlink fixture")
					}
				}
				got, e := s.Load()
				resultCode(t, got, e, ErrLocationUnsafe)
				// Only creator restores its deliberate negative artifacts after assertions.
				switch kind {
				case "mode":
					if os.Chmod(path, 0600) != nil {
						t.Fatal("creator restore")
					}
				case "symlink":
					if os.Remove(path) != nil || os.WriteFile(path, original, 0600) != nil {
						t.Fatal("creator restore")
					}
				case "hardlink":
					if os.Remove(l.dir+"/owned-link") != nil {
						t.Fatal("creator restore")
					}
				}
				if name != sqliteName && name != lockName {
					if os.Remove(path) != nil {
						t.Fatal("creator aux restore")
					}
				}
			})
		}
	}
	t.Run("safe-journal", func(t *testing.T) {
		l := newSQLiteLab(t)
		l.seed(t, emptyFixture())
		s := openSQLiteLab(t, l, ownedResolver())
		if os.WriteFile(l.dir+"/"+sqliteJournal, []byte("owned-not-hot"), 0600) != nil {
			t.Fatal("journal setup")
		}
		baseline := sqliteFingerprint(t, l)
		got, e := s.Load()
		resultCode(t, got, e, ErrIO)
		got, e = s.Commit(0, addition("Alpha"))
		resultCode(t, got, e, ErrIO)
		if sqliteFingerprint(t, l) != baseline {
			t.Fatal("ordinary journal changed")
		}
	})
	t.Run("root-mode", func(t *testing.T) {
		l := newSQLiteLab(t)
		l.seed(t, emptyFixture())
		s := openSQLiteLab(t, l, ownedResolver())
		if os.Chmod(l.dir, 0755) != nil {
			t.Fatal("root mode")
		}
		got, e := s.Load()
		resultCode(t, got, e, ErrLocationUnsafe)
		if os.Chmod(l.dir, 0700) != nil {
			t.Fatal("creator root restore")
		}
	})
}
func TestSQLitePostFlockReplacement(t *testing.T) {
	l := newSQLiteLab(t)
	l.seed(t, emptyFixture())
	s := openSQLiteLab(t, l, ownedResolver())
	holder, e := guardedFile(l.root, lockName, unix.O_RDWR)
	errCode(t, e, nil)
	errCode(t, nativeErrorOrNil(unix.Flock(holder, unix.LOCK_EX)), nil)
	done := make(chan error, 1)
	go func() { _, e := s.Load(); done <- e }()
	time.Sleep(40 * time.Millisecond)
	if unix.Renameat(l.root, lockName, l.root, "held-lock") != nil {
		t.Fatal("replace lock")
	}
	if os.WriteFile(l.dir+"/"+lockName, nil, 0600) != nil {
		t.Fatal("replacement lock")
	}
	unix.Flock(holder, unix.LOCK_UN)
	unix.Close(holder)
	errCode(t, <-done, ErrLocationUnsafe)
	if os.Remove(l.dir+"/"+lockName) != nil || unix.Renameat(l.root, "held-lock", l.root, lockName) != nil {
		t.Fatal("creator lock restore")
	}
}
func nativeErrorOrNil(e error) error {
	if e == nil {
		return nil
	}
	return nativeError(e)
}
func TestSQLiteCleanupRefusals(t *testing.T) {
	for _, name := range []string{sqliteName, lockName, sqliteJournal, "unknown"} {
		t.Run(name, func(t *testing.T) {
			l := newSQLiteLab(t)
			l.seed(t, emptyFixture())
			path := l.dir + "/" + name
			if name != sqliteName && name != lockName {
				if os.WriteFile(path, []byte("creator"), 0600) != nil {
					t.Fatal("negative entry")
				}
			}
			if name != "unknown" {
				if os.Chmod(path, 0644) != nil {
					t.Fatal("unsafe cleanup entry")
				}
			}
			entries, e := os.ReadDir(l.dir)
			if e != nil {
				t.Fatal("before inventory")
			}
			errCode(t, l.cleanup(), ErrLocationUnsafe)
			if l.root != -1 {
				t.Fatal("refused cleanup retained descriptor")
			}
			after, e := os.ReadDir(l.dir)
			if e != nil || len(after) != len(entries) {
				t.Fatal("cleanup partially deleted")
			}
			for i := range entries {
				if entries[i].Name() != after[i].Name() {
					t.Fatal("cleanup changed names")
				}
			}
			if name == "unknown" {
				if os.Remove(path) != nil {
					t.Fatal("creator unknown cleanup")
				}
			} else {
				if os.Chmod(path, 0600) != nil {
					t.Fatal("creator safe restore")
				}
			}
			root, st, e := openRoot(l.dir)
			errCode(t, e, nil)
			if !sameInode(&st, &l.original) {
				unix.Close(root)
				t.Fatal("root identity")
			}
			l.root = root
		})
	}
}
func TestSQLiteAbsentAndSeedRefusals(t *testing.T) {
	l := newSQLiteLab(t)
	s, e := OpenSQLiteFixture(l.dir, ownedResolver())
	if s != nil {
		s.Close()
		t.Fatal("absent initialized")
	}
	errCode(t, e, ErrNotFound)
	l.seed(t, emptyFixture())
	baseline := sqliteFingerprint(t, l)
	errCode(t, SeedSQLiteFixture(l.dir, emptyFixture(), ownedResolver()), ErrLocationUnsafe)
	errCode(t, SeedSQLiteFixture(l.dir, Snapshot{SchemaVersion: 2}, ownedResolver()), ErrUnsupported)
	if sqliteFingerprint(t, l) != baseline {
		t.Fatal("seed refusal changed")
	}
	b := bytes.Repeat([]byte{'x'}, maxFixture+1)
	_, e = DecodeFixture(b)
	errCode(t, e, ErrInvalid)
}
