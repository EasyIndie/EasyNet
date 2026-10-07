package sshlab

import (
	"bytes"
	"errors"
	"strings"
	"testing"
)

const good = `{"kind":"easynet-lab-result","schemaVersion":1,"operationId":"op_1","outcome":"unknown","ownerRetained":true,"outputBytes":2}`

func TestLabRecord(t *testing.T) {
	for _, outcome := range []string{"not-dispatched", "unknown", "fixture-complete-observed"} {
		owner, n := outcome != "not-dispatched", 3
		if !owner {
			n = 0
		}
		r := LabRecord{"easynet-lab-result", 1, "abc-1", outcome, owner, n}
		var buf bytes.Buffer
		if err := EncodeLabRecord(&buf, r); err != nil {
			t.Fatal(err)
		}
		got, err := DecodeLabRecord(&buf)
		if err != nil || got != r {
			t.Fatalf("%s: %#v %v", outcome, got, err)
		}
	}
	max := `{"kind":"easynet-lab-result","schemaVersion":1,"operationId":"x","outcome":"unknown","ownerRetained":true,"outputBytes":4096}`
	padded := max + strings.Repeat(" ", 4096-len(max))
	if _, err := DecodeLabRecord(strings.NewReader(padded)); err != nil {
		t.Fatal(err)
	}
	for _, input := range []string{
		strings.TrimSuffix(strings.Replace(good, `"kind"`, `"k\u0069nd"`, 1), `}`) + `,"kind":"easynet-lab-result"}`,
		strings.Replace(good, `"schemaVersion":1`, `"schemaVersion":1.0`, 1), strings.Replace(good, `"schemaVersion":1`, `"schemaVersion":1e0`, 1),
		strings.Replace(good, `"outputBytes":2`, `"outputBytes":-0`, 1), strings.Replace(good, `"outputBytes":2`, `"outputBytes":4097`, 1),
		strings.Replace(good, `"ownerRetained":true`, `"ownerRetained":null`, 1),
		strings.Replace(strings.Replace(strings.Replace(good, `"outcome":"unknown"`, `"outcome":"not-dispatched"`, 1), `"ownerRetained":true`, `"ownerRetained":null`, 1), `"outputBytes":2`, `"outputBytes":0`, 1),
		strings.Replace(good, `"outcome":"unknown"`, `"outcome":"unknown","extra":0`, 1),
		strings.Replace(good, `"kind":"easynet-lab-result"`, `"Kind":"easynet-lab-result"`, 1),
		strings.Replace(good, `"kind":"easynet-lab-result"`, `"kind":[]`, 1), strings.Replace(good, `"outcome":"unknown"`, `"outcome":{}`, 1),
		strings.Replace(good, `"outputBytes":2`, `"outputBytes":2.0`, 1), strings.Replace(good, `"outputBytes":2`, `"outputBytes":2e0`, 1),
		strings.Replace(good, `"operationId":"op_1"`, `"operationId":"`+strings.Repeat("a", 65)+`"`, 1),
		strings.Replace(good, `"operationId":"op_1"`, `"operationId":"a\nbad"`, 1), good + `{}`, `{"kind":`, "null", "{}", strings.Repeat(" ", 4097),
	} {
		if r, err := DecodeLabRecord(strings.NewReader(input)); !errors.Is(err, ErrInvalidLabRecord) || r != (LabRecord{}) {
			t.Fatalf("accepted/revealed %q: %#v %v", input, r, err)
		}
	}
	for _, id := range []string{strings.Repeat("a", 64), "abc-123"} {
		input := strings.Replace(good, `"operationId":"op_1"`, `"operationId":"`+id+`"`, 1)
		if _, err := DecodeLabRecord(strings.NewReader(input)); err != nil {
			t.Fatalf("valid ID %q: %v", id, err)
		}
	}
	for _, input := range []string{
		strings.Replace(strings.Replace(good, `"outcome":"unknown"`, `"outcome":"fixture-complete-observed"`, 1), `"ownerRetained":true`, `"ownerRetained":false`, 1),
		strings.Replace(good, `"outcome":"unknown"`, `"outcome":"not-dispatched"`, 1),
		strings.Replace(strings.Replace(good, `"outcome":"unknown"`, `"outcome":"not-dispatched"`, 1), `"outputBytes":2`, `"outputBytes":0`, 1),
	} {
		if _, err := DecodeLabRecord(strings.NewReader(input)); err == nil {
			t.Fatalf("accepted ownership mismatch: %s", input)
		}
	}
	invalidUTF8 := strings.Replace(good, `"operationId":"op_1"`, `"operationId":"`+string([]byte{0xff})+`"`, 1)
	if _, err := DecodeLabRecord(strings.NewReader(invalidUTF8)); err != ErrInvalidLabRecord {
		t.Fatal(err)
	}
	if _, err := DecodeLabRecord(failingReader{}); err != ErrLabRecordIO {
		t.Fatal(err)
	}
	var untouched bytes.Buffer
	if err := EncodeLabRecord(&untouched, LabRecord{}); err != ErrInvalidLabRecord || untouched.Len() != 0 {
		t.Fatal("invalid record wrote output")
	}
	var out bytes.Buffer
	if err := EncodeLabRecord(&out, LabRecord{"easynet-lab-result", 1, "x", "unknown", true, 0}); err != nil {
		t.Fatal(err)
	}
	for _, w := range []interface{ Write([]byte) (int, error) }{shortWriter{}, failingWriter{}} {
		if err := EncodeLabRecord(w, LabRecord{"easynet-lab-result", 1, "x", "unknown", true, 0}); err != ErrLabRecordIO {
			t.Fatal(err)
		}
	}
	if _, err := Summarize(Result{OperationID: "bad/id", Outcome: "not-dispatched"}); err != ErrInvalidLabRecord {
		t.Fatal(err)
	}
	r, err := Summarize(Result{OperationID: "x", Outcome: "unknown", OwnerRetained: true, Output: []byte("private-output")})
	var encoded bytes.Buffer
	if err != nil || EncodeLabRecord(&encoded, r) != nil || strings.Contains(encoded.String(), "private-output") || r.OutputBytes != 14 {
		t.Fatal("summary exposed output or lost byte count")
	}
}

type failingReader struct{}

func (failingReader) Read(p []byte) (int, error) { p[0] = 'x'; return 1, errors.New("secret") }

type shortWriter struct{}

func (shortWriter) Write([]byte) (int, error) { return 0, nil }

type failingWriter struct{}

func (failingWriter) Write([]byte) (int, error) { return 0, errors.New("secret") }
