package statelab

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"regexp"
	"sort"
	"unicode/utf8"
)

const maxFixture = 16 * 1024

type parsedObject map[string]any

var lexicalInteger = regexp.MustCompile(`^(0|[1-9][0-9]*)$`)

// parseValue rejects duplicate keys recursively while retaining JSON numbers lexically.
func parseValue(d *json.Decoder) (any, error) {
	t, err := d.Token()
	if err != nil {
		return nil, err
	}
	switch v := t.(type) {
	case json.Delim:
		switch v {
		case '{':
			o := parsedObject{}
			for d.More() {
				kt, e := d.Token()
				if e != nil {
					return nil, e
				}
				k, ok := kt.(string)
				if !ok {
					return nil, errors.New("bad object key")
				}
				if _, exists := o[k]; exists {
					return nil, fail(ErrInvalid)
				}
				x, e := parseValue(d)
				if e != nil {
					return nil, e
				}
				o[k] = x
			}
			end, e := d.Token()
			if e != nil || end != json.Delim('}') {
				return nil, errors.New("bad object")
			}
			return o, nil
		case '[':
			a := []any{}
			for d.More() {
				x, e := parseValue(d)
				if e != nil {
					return nil, e
				}
				a = append(a, x)
			}
			end, e := d.Token()
			if e != nil || end != json.Delim(']') {
				return nil, errors.New("bad array")
			}
			return a, nil
		default:
			return nil, errors.New("unexpected delimiter")
		}
	case json.Number:
		return v, nil
	default:
		return v, nil
	}
}
func decodeTree(b []byte) (any, error) {
	if len(b) > maxFixture {
		return nil, fail(ErrInvalid)
	}
	if !utf8.Valid(b) {
		return nil, fail(ErrCorrupt)
	}
	d := json.NewDecoder(bytes.NewReader(b))
	// Check every value's encoding before applying the single-object shape rule.
	var first json.RawMessage
	count := 0
	for {
		var raw json.RawMessage
		err := d.Decode(&raw)
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, fail(ErrCorrupt)
		}
		if count == 0 {
			first = raw
		}
		count++
	}
	if count == 0 {
		return nil, fail(ErrCorrupt)
	}
	if count > 1 {
		return nil, fail(ErrInvalid)
	}
	d = json.NewDecoder(bytes.NewReader(first))
	d.UseNumber()
	x, err := parseValue(d)
	if err != nil {
		var ec ErrorCode
		if errors.As(err, &ec) {
			return nil, ec
		}
		return nil, fail(ErrCorrupt)
	}
	return x, nil
}
func obj(v any, fields ...string) (parsedObject, error) {
	o, ok := v.(parsedObject)
	if !ok || len(o) != len(fields) {
		return nil, fail(ErrInvalid)
	}
	for _, f := range fields {
		if _, ok = o[f]; !ok {
			return nil, fail(ErrInvalid)
		}
	}
	return o, nil
}
func str(o parsedObject, k string) (string, error) {
	v, ok := o[k].(string)
	if !ok {
		return "", fail(ErrInvalid)
	}
	return v, nil
}
func uintNum(o parsedObject, k string, positive bool) (uint32, error) {
	s, ok := o[k].(json.Number)
	if !ok || !lexicalInteger.MatchString(string(s)) {
		return 0, fail(ErrInvalid)
	}
	var n uint64
	for _, c := range s {
		digit := uint64(c - '0')
		if n > (uint64(MaxGeneration)-digit)/10 {
			return 0, fail(ErrInvalid)
		}
		n = n*10 + digit
	}
	if positive && n == 0 {
		return 0, fail(ErrInvalid)
	}
	return uint32(n), nil
}
func array(o parsedObject, k string) ([]any, error) {
	a, ok := o[k].([]any)
	if !ok || len(a) > 4 {
		return nil, fail(ErrInvalid)
	}
	return a, nil
}
func parseSnapshot(v any) (Snapshot, error) {
	root, ok := v.(parsedObject)
	if !ok {
		return Snapshot{}, fail(ErrInvalid)
	}
	versionNumber, e := uintNum(root, "schemaVersion", false)
	if e != nil {
		return Snapshot{}, e
	}
	if versionNumber > 1 {
		return Snapshot{}, fail(ErrUnsupported)
	}
	var o parsedObject
	var err error
	if versionNumber == 0 {
		o, err = obj(v, "schemaVersion", "sequence", "targets", "profiles", "operations")
		if err == nil {
			o["generation"] = o["sequence"]
		}
	} else {
		o, err = obj(v, "schemaVersion", "generation", "targets", "profiles", "operations")
	}
	if err != nil {
		return Snapshot{}, err
	}
	sv, e := uintNum(o, "schemaVersion", false)
	if e != nil {
		return Snapshot{}, e
	}
	if sv > 1 {
		return Snapshot{}, fail(ErrUnsupported)
	}
	g, e := uintNum(o, "generation", false)
	if e != nil {
		return Snapshot{}, e
	}
	s := Snapshot{SchemaVersion: sv, Generation: g, Targets: []Target{}, Profiles: []Profile{}, Operations: []Operation{}}
	ta, e := array(o, "targets")
	if e != nil {
		return Snapshot{}, e
	}
	for _, v := range ta {
		q, e := obj(v, "id", "revision", "credentialRef")
		if e != nil {
			return Snapshot{}, e
		}
		id, e := str(q, "id")
		if e != nil {
			return Snapshot{}, e
		}
		rev, e := uintNum(q, "revision", true)
		if e != nil {
			return Snapshot{}, e
		}
		ref, e := str(q, "credentialRef")
		if e != nil {
			return Snapshot{}, e
		}
		s.Targets = append(s.Targets, Target{id, rev, ref})
	}
	pa, e := array(o, "profiles")
	if e != nil {
		return Snapshot{}, e
	}
	for _, v := range pa {
		q, e := obj(v, "id", "revision", "targetId", "runtimeId", "protocolId", "format", "configRef")
		if e != nil {
			return Snapshot{}, e
		}
		id, e := str(q, "id")
		if e != nil {
			return Snapshot{}, e
		}
		rev, e := uintNum(q, "revision", true)
		if e != nil {
			return Snapshot{}, e
		}
		tid, e := str(q, "targetId")
		if e != nil {
			return Snapshot{}, e
		}
		r, e := str(q, "runtimeId")
		if e != nil {
			return Snapshot{}, e
		}
		p, e := str(q, "protocolId")
		if e != nil {
			return Snapshot{}, e
		}
		f, e := str(q, "format")
		if e != nil {
			return Snapshot{}, e
		}
		c, e := str(q, "configRef")
		if e != nil {
			return Snapshot{}, e
		}
		s.Profiles = append(s.Profiles, Profile{id, rev, tid, r, p, f, c})
	}
	oa, e := array(o, "operations")
	if e != nil {
		return Snapshot{}, e
	}
	for _, v := range oa {
		q, e := obj(v, "operationId", "targetId", "planHash", "remoteState")
		if e != nil {
			return Snapshot{}, e
		}
		id, e := str(q, "operationId")
		if e != nil {
			return Snapshot{}, e
		}
		tid, e := str(q, "targetId")
		if e != nil {
			return Snapshot{}, e
		}
		h, e := str(q, "planHash")
		if e != nil {
			return Snapshot{}, e
		}
		r, e := str(q, "remoteState")
		if e != nil {
			return Snapshot{}, e
		}
		s.Operations = append(s.Operations, Operation{id, tid, h, r})
	}
	return s, nil
}
func DecodeFixture(b []byte) (Snapshot, error) {
	v, e := decodeTree(b)
	if e != nil {
		return Snapshot{}, e
	}
	s, e := parseSnapshot(v)
	if e != nil {
		return Snapshot{}, e
	}
	if e = validateValues(s); e != nil {
		return Snapshot{}, e
	}
	if e = validateRelations(s); e != nil {
		return Snapshot{}, e
	}
	return s, nil
}
func EncodeFixture(s Snapshot, r Resolver) ([]byte, error) {
	if err := validateValues(s); err != nil {
		return nil, err
	}
	if err := validateRelations(s); err != nil {
		return nil, err
	}
	if s.SchemaVersion == 0 {
		if err := validateRefs(s, r); err != nil {
			return nil, err
		}
	} else if err := validateV1(s, r); err != nil {
		return nil, err
	}
	s = clone(s)
	sort.Slice(s.Targets, func(i, j int) bool { return s.Targets[i].ID < s.Targets[j].ID })
	sort.Slice(s.Profiles, func(i, j int) bool { return s.Profiles[i].ID < s.Profiles[j].ID })
	sort.Slice(s.Operations, func(i, j int) bool { return s.Operations[i].OperationID < s.Operations[j].OperationID })
	var v any
	if s.SchemaVersion == 0 {
		v = struct {
			SchemaVersion uint32      `json:"schemaVersion"`
			Sequence      uint32      `json:"sequence"`
			Targets       []Target    `json:"targets"`
			Profiles      []Profile   `json:"profiles"`
			Operations    []Operation `json:"operations"`
		}{0, s.Generation, s.Targets, s.Profiles, s.Operations}
	} else {
		v = struct {
			SchemaVersion uint32      `json:"schemaVersion"`
			Generation    uint32      `json:"generation"`
			Targets       []Target    `json:"targets"`
			Profiles      []Profile   `json:"profiles"`
			Operations    []Operation `json:"operations"`
		}{1, s.Generation, s.Targets, s.Profiles, s.Operations}
	}
	b, e := json.Marshal(v)
	if e != nil || len(b) > maxFixture {
		return nil, fail(ErrInvalid)
	}
	return b, nil
}
