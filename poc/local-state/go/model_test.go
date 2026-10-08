package statelab

import (
	"bytes"
	"strings"
	"testing"
)

type fixtureResolver struct {
	targets          map[Target]bool
	profiles         map[Profile]bool
	credentialStatus Resolution
	configStatus     Resolution
}

var resolutionFailures = []struct {
	got  Resolution
	want ErrorCode
}{{Missing, ErrUnresolved}, {Locked, ErrSecretLocked}, {Mismatch, ErrRefMismatch}, {99, ErrRefMismatch}}

func (r fixtureResolver) ResolveCredential(t Target) Resolution {
	if r.credentialStatus != Missing {
		return r.credentialStatus
	}
	if r.targets[t] {
		return Available
	}
	return Missing
}
func (r fixtureResolver) ResolveConfig(p Profile) Resolution {
	if r.configStatus != Missing {
		return r.configStatus
	}
	if r.profiles[p] {
		return Available
	}
	return Missing
}
func resolverFor(snapshots ...Snapshot) Resolver {
	r := fixtureResolver{targets: map[Target]bool{}, profiles: map[Profile]bool{}}
	for _, s := range snapshots {
		for _, t := range s.Targets {
			r.targets[t] = true
		}
		for _, p := range s.Profiles {
			r.profiles[p] = true
		}
	}
	return r
}
func empty() Snapshot {
	return Snapshot{SchemaVersion: 1, Generation: 0, Targets: []Target{}, Profiles: []Profile{}, Operations: []Operation{}}
}
func code(t *testing.T, err error, want ErrorCode) {
	t.Helper()
	if err == nil || err.Error() != want.Error() {
		t.Fatalf("got error %v, want %s", err, want)
	}
}
func sample() Snapshot {
	s := empty()
	s.Targets = []Target{{"t_one", 1, "cred_one"}}
	s.Profiles = []Profile{{"p_one", 1, "t_one", "hysteria2-native", "hysteria2", "hysteria2-native-config", "config_one"}}
	s.Operations = []Operation{{"op_one", "t_one", "sha256:" + strings.Repeat("a", 64), "unknown"}}
	return s
}

func TestClosedDecodeAndCanonicalRoundTrip(t *testing.T) {
	emptyBytes, err := EncodeFixture(empty(), resolverFor(empty()))
	if err != nil || string(emptyBytes) != `{"schemaVersion":1,"generation":0,"targets":[],"profiles":[],"operations":[]}` {
		t.Fatalf("empty fixture encoding: %s %v", emptyBytes, err)
	}
	s := sample()
	s.Targets = append(s.Targets, Target{"t_two", 1, "cred_two"})
	s.Targets[0], s.Targets[1] = s.Targets[1], s.Targets[0]
	b, e := EncodeFixture(s, resolverFor(s))
	if e != nil {
		t.Fatal(e)
	}
	got, e := DecodeFixture(b)
	if e != nil {
		t.Fatal(e)
	}
	if got.Targets[0].ID != "t_one" {
		t.Fatal("decoded ordering changed")
	}
	encoded, e := EncodeFixture(got, resolverFor(got))
	if e != nil {
		t.Fatal(e)
	}
	if !bytes.Equal(b, encoded) {
		t.Fatal("canonical output differs")
	}
	if got.Targets == nil || got.Profiles == nil || got.Operations == nil {
		t.Fatal("empty arrays must remain arrays")
	}
}
func TestDecodeRejectsLexicalShapeAndDuplicateKeys(t *testing.T) {
	base := `{"schemaVersion":1,"generation":0,"targets":[],"profiles":[],"operations":[]}`
	cases := []string{
		strings.Replace(base, `"generation":0`, `"generation":-0`, 1), strings.Replace(base, `"generation":0`, `"generation":0.0`, 1), strings.Replace(base, `"generation":0`, `"generation":1e0`, 1),
		strings.Replace(base, `"generation":0`, `"generation":2147483648`, 1), strings.Replace(base, `"operations":[]`, `"operations":null`, 1),
		strings.Replace(base, `"operations":[]`, `"extra":1,"operations":[]`, 1),
		`{"schemaVersion":1,"generation":0,"targets":[],"profiles":[],"operations":[],"\u0067eneration":1}`,
		`{"schemaVersion":1,"generation":0,"targets":[{"id":"t_one","id":"t_two","revision":1,"credentialRef":"cred_one"}],"profiles":[],"operations":[]}`,
	}
	for _, in := range cases {
		if _, e := DecodeFixture([]byte(in)); e == nil || e == ErrCorrupt {
			t.Fatalf("accepted or misclassified %s: %v", in, e)
		}
	}
	boundary := []byte(base + strings.Repeat(" ", maxFixture-len(base)))
	if _, e := DecodeFixture(boundary); e != nil {
		t.Fatalf("exact limit rejected: %v", e)
	}
	code(t, errDecode(append(boundary, ' ')), ErrInvalid)
	bad := append([]byte(base), 0xff)
	code(t, errDecode(bad), ErrCorrupt)
}
func errDecode(b []byte) error { _, e := DecodeFixture(b); return e }
func TestDecodeVersionsAndMalformedInput(t *testing.T) {
	v0 := `{"schemaVersion":0,"sequence":4,"targets":[],"profiles":[],"operations":[]}`
	s, e := DecodeFixture([]byte(v0))
	if e != nil || s.SchemaVersion != 0 || s.Generation != 4 {
		t.Fatalf("v0 parse: %#v %v", s, e)
	}
	code(t, ValidateV1(s, nil), ErrMigrationRequired)
	if _, e = DecodeFixture([]byte(`{"schemaVersion":2,"generation":0,"targets":[],"profiles":[],"operations":[]}`)); e != ErrUnsupported {
		code(t, e, ErrUnsupported)
	}
	for _, b := range [][]byte{[]byte("{"), []byte(`{} x`), {0xff}} {
		code(t, errDecode(b), ErrCorrupt)
	}
	code(t, errDecode([]byte(`{} {}`)), ErrInvalid)
}
func TestDecodeNumericTokenTypesAndCompleteStream(t *testing.T) {
	base := `{"schemaVersion":1,"generation":0,"targets":[],"profiles":[],"operations":[]}`
	v0 := `{"schemaVersion":0,"sequence":0,"targets":[],"profiles":[],"operations":[]}`
	s := sample()
	populated, e := EncodeFixture(s, resolverFor(s))
	if e != nil {
		t.Fatal(e)
	}
	cases := []struct {
		name string
		in   string
		want ErrorCode
	}{
		{"quoted v1 schema", strings.Replace(base, `"schemaVersion":1`, `"schemaVersion":"1"`, 1), ErrInvalid},
		{"quoted generation", strings.Replace(base, `"generation":0`, `"generation":"0"`, 1), ErrInvalid},
		{"quoted v0 schema", strings.Replace(v0, `"schemaVersion":0`, `"schemaVersion":"0"`, 1), ErrInvalid},
		{"quoted sequence", strings.Replace(v0, `"sequence":0`, `"sequence":"0"`, 1), ErrInvalid},
		{"quoted target revision", strings.Replace(string(populated), `"revision":1`, `"revision":"1"`, 1), ErrInvalid},
		{"quoted profile revision", strings.Replace(string(populated), `"id":"p_one","revision":1`, `"id":"p_one","revision":"1"`, 1), ErrInvalid},
		{"extra object", base + ` {}`, ErrInvalid},
		{"extra array", base + ` []`, ErrInvalid},
		{"extra number", base + ` 0`, ErrInvalid},
		{"extra string", base + ` "complete"`, ErrInvalid},
		{"extra literal", base + ` true`, ErrInvalid},
		{"multiple complete extras", base + ` {} [] null`, ErrInvalid},
		{"unclosed second object", base + ` {`, ErrCorrupt},
		{"unclosed second array", base + ` [`, ErrCorrupt},
		{"malformed second object", base + ` {"x":}`, ErrCorrupt},
		{"incomplete second string", base + ` "unfinished`, ErrCorrupt},
		{"incomplete second literal", base + ` tru`, ErrCorrupt},
		{"incomplete second number", base + ` 1e`, ErrCorrupt},
		{"unclosed third value", base + ` {} [`, ErrCorrupt},
		{"malformed fourth value", base + ` {} [] {"x":}`, ErrCorrupt},
		{"junk after complete extras", base + ` {} null x`, ErrCorrupt},
	}
	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			got, err := DecodeFixture([]byte(test.in))
			code(t, err, test.want)
			if got.SchemaVersion != 0 || got.Generation != 0 || got.Targets != nil || got.Profiles != nil || got.Operations != nil {
				t.Fatalf("error returned partial snapshot: %#v", got)
			}
		})
	}
}
func TestReferenceResolutionAndValidation(t *testing.T) {
	s := sample()
	if e := ValidateV1(s, nil); e != ErrUnresolved {
		code(t, e, ErrUnresolved)
	}
	for _, test := range resolutionFailures {
		r := fixtureResolver{credentialStatus: test.got}
		code(t, ValidateV1(s, r), test.want)
	}
	for _, test := range resolutionFailures {
		r := resolverFor(s).(fixtureResolver)
		if test.got == Missing {
			r.profiles = map[Profile]bool{}
		} else {
			r.configStatus = test.got
		}
		code(t, ValidateV1(s, r), test.want)
	}
	s.Profiles[0].Format = "other"
	code(t, ValidateV1(s, resolverFor(s)), ErrInvalid)
}
func TestEncodeDoesNotMutateAndRejectsInvalid(t *testing.T) {
	s := sample()
	before := append([]Target(nil), s.Targets...)
	if _, e := EncodeFixture(s, resolverFor(s)); e != nil {
		t.Fatal(e)
	}
	if s.Targets[0] != before[0] {
		t.Fatal("input mutated")
	}
	s.Generation = MaxGeneration + 1
	b, e := EncodeFixture(s, resolverFor(s))
	if b != nil || e != ErrInvalid {
		t.Fatalf("got %q %v", b, e)
	}
}
func TestMigrationExactCloneAndExhaustion(t *testing.T) {
	s := sample()
	s.SchemaVersion = 0
	s.Generation = 9
	n, e := StageMigration(s, resolverFor(s))
	if e != nil {
		t.Fatal(e)
	}
	if n.SchemaVersion != 1 || n.Generation != 10 || n.Targets[0] != s.Targets[0] || n.Operations[0] != s.Operations[0] {
		t.Fatal("migration changed records")
	}
	if e = ValidateMigration(s, n, 9, resolverFor(s)); e != nil {
		t.Fatal(e)
	}
	bad := clone(n)
	bad.Targets[0].CredentialRef = "cred_other"
	code(t, ValidateMigration(s, bad, 9, resolverFor(s)), ErrInvalid)
	s.Generation = MaxGeneration
	_, e = StageMigration(s, resolverFor(s))
	code(t, e, ErrExhausted)
}
func TestCommitCASRevisionsAndImmutableMirrors(t *testing.T) {
	current := sample()
	next := clone(current)
	next.Generation = 1
	next.Targets[0].Revision = 2
	if e := ValidateCommit(current, next, 0, resolverFor(current, next)); e != nil {
		t.Fatal(e)
	}
	staleCandidate := clone(next)
	staleCandidate.Generation = 2
	code(t, ValidateCommit(current, staleCandidate, 1, resolverFor(current, next, staleCandidate)), ErrConflict)
	bad := clone(next)
	bad.Targets[0].Revision = 3
	code(t, ValidateCommit(current, bad, 0, resolverFor(current, next, bad)), ErrInvalid)
	bad = clone(next)
	bad.Operations = nil
	code(t, ValidateCommit(current, bad, 0, resolverFor(current, next, bad)), ErrBindingImmutable)
	bad = clone(next)
	bad.Operations[0].PlanHash = "sha256:" + strings.Repeat("b", 64)
	code(t, ValidateCommit(current, bad, 0, resolverFor(current, next, bad)), ErrBindingImmutable)
	current.Generation = MaxGeneration
	next.Generation = 0
	code(t, ValidateCommit(current, next, MaxGeneration, resolverFor(current, next)), ErrExhausted)
}
func TestMigrationConflictAndOrderIndependent(t *testing.T) {
	s := sample()
	s.SchemaVersion = 0
	n, e := StageMigration(s, resolverFor(s))
	if e != nil {
		t.Fatal(e)
	}
	if e = ValidateMigration(s, n, 0, resolverFor(s)); e != nil {
		t.Fatal(e)
	}
	if e = ValidateMigration(n, n, 0, resolverFor(n)); e != ErrConflict {
		code(t, e, ErrConflict)
	}
	s.Targets = append(s.Targets, Target{"t_two", 1, "cred_two"})
	n, e = StageMigration(s, resolverFor(s))
	if e != nil {
		t.Fatal(e)
	}
	bad := clone(n)
	bad.Targets[0], bad.Targets[1] = bad.Targets[1], bad.Targets[0]
	if e = ValidateMigration(s, bad, 0, resolverFor(s)); e != nil {
		t.Fatal(e)
	}
}
