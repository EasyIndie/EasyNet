package sshlab

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"regexp"
	"unicode/utf8"
)

var (
	ErrInvalidLabRecord = errors.New("invalid lab record")
	ErrLabRecordIO      = errors.New("lab record I/O failure")
	labID               = regexp.MustCompile(`^[A-Za-z0-9_-]{1,64}$`)
	labBytes            = regexp.MustCompile(`^(0|[1-9][0-9]*)$`)
)

type LabRecord struct {
	Kind          string `json:"kind"`
	SchemaVersion int    `json:"schemaVersion"`
	OperationID   string `json:"operationId"`
	Outcome       string `json:"outcome"`
	OwnerRetained bool   `json:"ownerRetained"`
	OutputBytes   int    `json:"outputBytes"`
}

func validRecord(r LabRecord) bool {
	if r.Kind != "easynet-lab-result" || r.SchemaVersion != 1 || !labID.MatchString(r.OperationID) || r.OutputBytes < 0 || r.OutputBytes > 4096 {
		return false
	}
	switch r.Outcome {
	case "not-dispatched":
		return !r.OwnerRetained && r.OutputBytes == 0
	case "unknown", "fixture-complete-observed":
		return r.OwnerRetained
	}
	return false
}

func Summarize(result Result) (LabRecord, error) {
	r := LabRecord{"easynet-lab-result", 1, result.OperationID, result.Outcome, result.OwnerRetained, len(result.Output)}
	if !validRecord(r) {
		return LabRecord{}, ErrInvalidLabRecord
	}
	return r, nil
}

func DecodeLabRecord(reader io.Reader) (LabRecord, error) {
	bad := func() (LabRecord, error) { return LabRecord{}, ErrInvalidLabRecord }
	if reader == nil {
		return bad()
	}
	data, err := io.ReadAll(io.LimitReader(reader, 4097))
	if err != nil {
		return LabRecord{}, ErrLabRecordIO
	}
	if len(data) > 4096 || !utf8.Valid(data) {
		return bad()
	}
	dec := json.NewDecoder(bytes.NewReader(data))
	tok, err := dec.Token()
	if err != nil || tok != json.Delim('{') {
		return bad()
	}
	fields := make(map[string]json.RawMessage, 6)
	for dec.More() {
		keyToken, e := dec.Token()
		key, ok := keyToken.(string)
		if e != nil || !ok {
			return bad()
		}
		if _, exists := fields[key]; exists {
			return bad()
		}
		var raw json.RawMessage
		if dec.Decode(&raw) != nil {
			return bad()
		}
		fields[key] = raw
	}
	if _, err = dec.Token(); err != nil || len(fields) != 6 {
		return bad()
	}
	var extra any
	if dec.Decode(&extra) != io.EOF {
		return bad()
	}
	for _, key := range []string{"kind", "schemaVersion", "operationId", "outcome", "ownerRetained", "outputBytes"} {
		raw, ok := fields[key]
		if !ok || bytes.Equal(raw, []byte("null")) {
			return bad()
		}
	}
	var r LabRecord
	if json.Unmarshal(fields["kind"], &r.Kind) != nil || json.Unmarshal(fields["operationId"], &r.OperationID) != nil || json.Unmarshal(fields["outcome"], &r.Outcome) != nil || json.Unmarshal(fields["ownerRetained"], &r.OwnerRetained) != nil {
		return bad()
	}
	if string(fields["schemaVersion"]) != "1" || !labBytes.Match(fields["outputBytes"]) {
		return bad()
	}
	if json.Unmarshal(fields["schemaVersion"], &r.SchemaVersion) != nil || json.Unmarshal(fields["outputBytes"], &r.OutputBytes) != nil || !validRecord(r) {
		return bad()
	}
	return r, nil
}

func EncodeLabRecord(writer io.Writer, record LabRecord) error {
	if !validRecord(record) {
		return ErrInvalidLabRecord
	}
	if writer == nil {
		return ErrLabRecordIO
	}
	data, err := json.Marshal(record)
	if err != nil {
		return ErrInvalidLabRecord
	}
	n, err := writer.Write(data)
	if err != nil || n != len(data) {
		return ErrLabRecordIO
	}
	return nil
}
