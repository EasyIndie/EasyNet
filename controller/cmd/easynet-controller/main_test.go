package main

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

type failingWriter struct{}

func (failingWriter) Write([]byte) (int, error) {
	return 0, errors.New("private writer failure")
}

func TestVersion(t *testing.T) {
	want, err := os.ReadFile(filepath.Join("testdata", "version.txt"))
	if err != nil {
		t.Fatal("read version fixture")
	}
	var out, errOut bytes.Buffer
	if code := run([]string{"--version"}, &out, &errOut); code != 0 {
		t.Fatalf("exit = %d, want 0", code)
	}
	if !bytes.Equal(out.Bytes(), want) {
		t.Fatalf("stdout = %q, want fixture %q", out.Bytes(), want)
	}
	if errOut.Len() != 0 {
		t.Fatalf("stderr = %q, want empty", errOut.String())
	}
}

func TestInvalidArguments(t *testing.T) {
	cases := []struct {
		name string
		args []string
	}{
		{name: "no arguments"},
		{name: "unknown", args: []string{"--unknown"}},
		{name: "extra argument", args: []string{"--version", "extra"}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var out, errOut bytes.Buffer
			if code := run(tc.args, &out, &errOut); code != 2 {
				t.Fatalf("exit = %d, want 2", code)
			}
			if out.Len() != 0 {
				t.Fatalf("stdout = %q, want empty", out.String())
			}
			if errOut.String() != usage {
				t.Fatalf("stderr = %q, want fixed usage %q", errOut.String(), usage)
			}
			for _, arg := range tc.args {
				if arg == "--version" {
					continue
				}
				if bytes.Contains(errOut.Bytes(), []byte(arg)) {
					t.Fatalf("stderr echoed argument %q", arg)
				}
			}
		})
	}
}

func TestVersionOutputFailureIsRedacted(t *testing.T) {
	var errOut bytes.Buffer
	if code := run([]string{"--version"}, failingWriter{}, &errOut); code != 1 {
		t.Fatalf("exit = %d, want 1", code)
	}
	if errOut.Len() != 0 {
		t.Fatalf("stderr = %q, want empty", errOut.String())
	}
}
