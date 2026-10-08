package statelab

import (
	"regexp"
	"sort"
)

const MaxGeneration uint32 = 2147483647

type ErrorCode uint8

const (
	ErrInvalid ErrorCode = iota + 1
	ErrCorrupt
	ErrUnsupported
	ErrMigrationRequired
	ErrUnresolved
	ErrSecretLocked
	ErrRefMismatch
	ErrConflict
	ErrExhausted
	ErrBindingImmutable
	ErrNotFound
	ErrLocationUnsafe
	ErrIO
	ErrCommitUnknown
)

func (e ErrorCode) Error() string {
	switch e {
	case ErrCorrupt:
		return "state-corrupt"
	case ErrUnsupported:
		return "state-schema-unsupported"
	case ErrMigrationRequired:
		return "state-migration-required"
	case ErrUnresolved:
		return "state-ref-unresolved"
	case ErrSecretLocked:
		return "state-secret-locked"
	case ErrRefMismatch:
		return "state-ref-mismatch"
	case ErrConflict:
		return "state-generation-conflict"
	case ErrExhausted:
		return "state-generation-exhausted"
	case ErrBindingImmutable:
		return "state-binding-immutable"
	case ErrNotFound:
		return "state-not-found"
	case ErrLocationUnsafe:
		return "state-location-unsafe"
	case ErrIO:
		return "state-io"
	case ErrCommitUnknown:
		return "state-commit-unknown"
	default:
		return "state-invalid"
	}
}
func fail(e ErrorCode) error { return e }

type Snapshot struct {
	SchemaVersion uint32
	Generation    uint32
	Targets       []Target
	Profiles      []Profile
	Operations    []Operation
}
type Target struct {
	ID            string `json:"id"`
	Revision      uint32 `json:"revision"`
	CredentialRef string `json:"credentialRef"`
}
type Profile struct {
	ID         string `json:"id"`
	Revision   uint32 `json:"revision"`
	TargetID   string `json:"targetId"`
	RuntimeID  string `json:"runtimeId"`
	ProtocolID string `json:"protocolId"`
	Format     string `json:"format"`
	ConfigRef  string `json:"configRef"`
}
type Operation struct {
	OperationID string `json:"operationId"`
	TargetID    string `json:"targetId"`
	PlanHash    string `json:"planHash"`
	RemoteState string `json:"remoteState"`
}

type Resolution uint8

const (
	Missing Resolution = iota
	Available
	Locked
	Mismatch
)

type Resolver interface {
	ResolveCredential(Target) Resolution
	ResolveConfig(Profile) Resolution
}

var idPattern = regexp.MustCompile(`^[A-Za-z][A-Za-z0-9_-]{0,63}$`)
var credPattern = regexp.MustCompile(`^cred_[A-Za-z0-9_-]{1,64}$`)
var configPattern = regexp.MustCompile(`^config_[A-Za-z0-9_-]{1,64}$`)
var hashPattern = regexp.MustCompile(`^sha256:[0-9a-f]{64}$`)

func clone(s Snapshot) Snapshot {
	s.Targets = append([]Target{}, s.Targets...)
	s.Profiles = append([]Profile{}, s.Profiles...)
	s.Operations = append([]Operation{}, s.Operations...)
	return s
}
func validateValues(s Snapshot) error {
	if s.SchemaVersion > 1 {
		return fail(ErrUnsupported)
	}
	if s.Generation > MaxGeneration {
		return fail(ErrInvalid)
	}
	ids := map[string]bool{}
	for _, t := range s.Targets {
		if !idPattern.MatchString(t.ID) || ids[t.ID] || t.Revision == 0 || t.Revision > MaxGeneration || !credPattern.MatchString(t.CredentialRef) {
			return fail(ErrInvalid)
		}
		ids[t.ID] = true
	}
	if len(s.Targets) > 4 {
		return fail(ErrInvalid)
	}
	ids = map[string]bool{}
	for _, p := range s.Profiles {
		if !idPattern.MatchString(p.ID) || ids[p.ID] || p.Revision == 0 || p.Revision > MaxGeneration || !idPattern.MatchString(p.TargetID) || !configPattern.MatchString(p.ConfigRef) {
			return fail(ErrInvalid)
		}
		tuple := p.RuntimeID == "hysteria2-native" && p.ProtocolID == "hysteria2" && p.Format == "hysteria2-native-config" || p.RuntimeID == "amneziawg-native" && p.ProtocolID == "amneziawg" && p.Format == "amneziawg-native-config"
		if !tuple {
			return fail(ErrInvalid)
		}
		ids[p.ID] = true
	}
	if len(s.Profiles) > 4 {
		return fail(ErrInvalid)
	}
	ids = map[string]bool{}
	for _, o := range s.Operations {
		if !idPattern.MatchString(o.OperationID) || ids[o.OperationID] || !idPattern.MatchString(o.TargetID) || !hashPattern.MatchString(o.PlanHash) || o.RemoteState != "unknown" {
			return fail(ErrInvalid)
		}
		ids[o.OperationID] = true
	}
	if len(s.Operations) > 4 {
		return fail(ErrInvalid)
	}
	return nil
}
func validateRelations(s Snapshot) error {
	t := map[string]bool{}
	for _, x := range s.Targets {
		t[x.ID] = true
	}
	for _, p := range s.Profiles {
		if !t[p.TargetID] {
			return fail(ErrUnresolved)
		}
	}
	for _, o := range s.Operations {
		if !t[o.TargetID] {
			return fail(ErrUnresolved)
		}
	}
	return nil
}
func validateRefs(s Snapshot, r Resolver) error {
	if r == nil {
		for _, t := range s.Targets {
			if t.CredentialRef != "" {
				return fail(ErrUnresolved)
			}
		}
		if len(s.Profiles) > 0 {
			return fail(ErrUnresolved)
		}
		return nil
	}
	for _, t := range s.Targets {
		x := r.ResolveCredential(t)
		switch x {
		case Missing:
			return fail(ErrUnresolved)
		case Locked:
			return fail(ErrSecretLocked)
		case Available:

		case Mismatch:
			return fail(ErrRefMismatch)
		default:
			return fail(ErrRefMismatch)
		}
	}
	for _, p := range s.Profiles {
		x := r.ResolveConfig(p)
		switch x {
		case Missing:
			return fail(ErrUnresolved)
		case Locked:
			return fail(ErrSecretLocked)
		case Available:

		case Mismatch:
			return fail(ErrRefMismatch)
		default:
			return fail(ErrRefMismatch)
		}
	}
	return nil
}
func validateV1(s Snapshot, r Resolver) error {
	if s.SchemaVersion == 0 {
		return fail(ErrMigrationRequired)
	}
	if s.SchemaVersion > 1 {
		return fail(ErrUnsupported)
	}
	if err := validateValues(s); err != nil {
		return err
	}
	if err := validateRelations(s); err != nil {
		return err
	}
	return validateRefs(s, r)
}
func ValidateV1(s Snapshot, r Resolver) error { return validateV1(s, r) }
func StageMigration(s Snapshot, r Resolver) (Snapshot, error) {
	if s.SchemaVersion != 0 {
		if s.SchemaVersion > 1 {
			return Snapshot{}, fail(ErrUnsupported)
		}
		return Snapshot{}, fail(ErrInvalid)
	}
	if err := validateValues(s); err != nil {
		return Snapshot{}, err
	}
	if err := validateRelations(s); err != nil {
		return Snapshot{}, err
	}
	if err := validateRefs(s, r); err != nil {
		return Snapshot{}, err
	}
	if s.Generation == MaxGeneration {
		return Snapshot{}, fail(ErrExhausted)
	}
	n := clone(s)
	n.SchemaVersion = 1
	n.Generation++
	return n, nil
}
func ValidateCommit(current, next Snapshot, expected uint32, r Resolver) error {
	if expected > MaxGeneration {
		return fail(ErrInvalid)
	}
	if err := validateV1(current, r); err != nil {
		return err
	}
	if expected == MaxGeneration && current.Generation == expected {
		return fail(ErrExhausted)
	}
	if err := validateV1(next, r); err != nil {
		return err
	}
	if next.Generation != expected+1 {
		return fail(ErrInvalid)
	}
	if current.Generation != expected {
		return fail(ErrConflict)
	}
	for _, old := range current.Operations {
		found := false
		for _, n := range next.Operations {
			if n.OperationID == old.OperationID {
				found = true
				if n != old {
					return fail(ErrBindingImmutable)
				}
				break
			}
		}
		if !found {
			return fail(ErrBindingImmutable)
		}
	}
	if err := revisions(current.Targets, next.Targets); err != nil {
		return err
	}
	if err := profileRevisions(current.Profiles, next.Profiles); err != nil {
		return err
	}
	return nil
}
func revisions(a, b []Target) error {
	m := map[string]Target{}
	for _, x := range a {
		m[x.ID] = x
	}
	for _, x := range b {
		if o, ok := m[x.ID]; ok {
			if x == o {
				continue
			}
			if x.Revision != o.Revision+1 {
				return fail(ErrInvalid)
			}
		}
	}
	return nil
}
func profileRevisions(a, b []Profile) error {
	m := map[string]Profile{}
	for _, x := range a {
		m[x.ID] = x
	}
	for _, x := range b {
		if o, ok := m[x.ID]; ok {
			if x == o {
				continue
			}
			if x.Revision != o.Revision+1 {
				return fail(ErrInvalid)
			}
		}
	}
	return nil
}
func logicalEqual(a, b Snapshot) bool {
	if a.SchemaVersion != b.SchemaVersion || a.Generation != b.Generation || len(a.Targets) != len(b.Targets) || len(a.Profiles) != len(b.Profiles) || len(a.Operations) != len(b.Operations) {
		return false
	}
	a = clone(a)
	b = clone(b)
	sort.Slice(a.Targets, func(i, j int) bool { return a.Targets[i].ID < a.Targets[j].ID })
	sort.Slice(b.Targets, func(i, j int) bool { return b.Targets[i].ID < b.Targets[j].ID })
	sort.Slice(a.Profiles, func(i, j int) bool { return a.Profiles[i].ID < a.Profiles[j].ID })
	sort.Slice(b.Profiles, func(i, j int) bool { return b.Profiles[i].ID < b.Profiles[j].ID })
	sort.Slice(a.Operations, func(i, j int) bool { return a.Operations[i].OperationID < a.Operations[j].OperationID })
	sort.Slice(b.Operations, func(i, j int) bool { return b.Operations[i].OperationID < b.Operations[j].OperationID })
	for i := range a.Targets {
		if a.Targets[i] != b.Targets[i] {
			return false
		}
	}
	for i := range a.Profiles {
		if a.Profiles[i] != b.Profiles[i] {
			return false
		}
	}
	for i := range a.Operations {
		if a.Operations[i] != b.Operations[i] {
			return false
		}
	}
	return true
}
func ValidateMigration(current, staged Snapshot, expected uint32, r Resolver) error {
	if expected > MaxGeneration {
		return fail(ErrInvalid)
	}
	if current.SchemaVersion == 1 {
		return fail(ErrConflict)
	}
	if current.SchemaVersion > 1 {
		return fail(ErrUnsupported)
	}
	if current.SchemaVersion != 0 {
		return fail(ErrInvalid)
	}
	if current.Generation != expected {
		return fail(ErrConflict)
	}
	if err := validateValues(current); err != nil {
		return err
	}
	if err := validateRelations(current); err != nil {
		return err
	}
	if err := validateRefs(current, r); err != nil {
		return err
	}
	if expected == MaxGeneration {
		return fail(ErrExhausted)
	}
	want, e := StageMigration(current, r)
	if e != nil {
		return e
	}
	if !logicalEqual(want, staged) {
		return fail(ErrInvalid)
	}
	return nil
}
