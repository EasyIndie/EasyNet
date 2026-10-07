package main

import (
	"bytes"
	"context"
	"errors"
	"io"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

const canonical = `{"kind":"easynet-lab-result","schemaVersion":1,"operationId":"fixture_1","outcome":"unknown","ownerRetained":true,"outputBytes":4}`

// No embedded buffer: every subprocess write goes through the bound.
type cappedWriter struct{ data []byte }

func (w *cappedWriter) Write(p []byte) (int, error) {
	if len(p) > 4096-len(w.data) {
		return 0, errors.New("fixture output bound exceeded")
	}
	w.data = append(w.data, p...)
	return len(p), nil
}

func command(t *testing.T, timeout time.Duration, input string, name string, args ...string) (string, string, error) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.WaitDelay = time.Second
	cmd.Stdin = strings.NewReader(input)
	var stdout, stderr cappedWriter
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	err := cmd.Run()
	if ctx.Err() != nil {
		t.Fatalf("fixture command exceeded deadline: %v", ctx.Err())
	}
	return string(stdout.data), string(stderr.data), err
}

func TestBinary(t *testing.T) {
	goTool := filepath.Join(runtime.GOROOT(), "bin", "go")
	binary := filepath.Join(t.TempDir(), "labresult")
	out, diagnostic, err := command(t, 15*time.Second, "", goTool, "build", "-o", binary, ".")
	if err != nil || out != "" || diagnostic != "" {
		t.Fatalf("build failed: %v, stdout %q, stderr %q", err, out, diagnostic)
	}
	cases := []struct {
		name, input, output, diagnostic string
		args                            []string
	}{
		{"canonical", canonical, canonical, "", nil},
		{"normalize", " \n" + canonical + "\t ", canonical, "", nil},
		{"input boundary", canonical + strings.Repeat(" ", 4096-len(canonical)), canonical, "", nil},
		{"empty", "", "", "invalid lab input\n", nil},
		{"malformed", `{"sensitive":"fixture-secret"`, "", "invalid lab input\n", nil},
		{"duplicate", strings.Replace(canonical, `"kind":`, `"kind":"easynet-lab-result","kind":`, 1), "", "invalid lab input\n", nil},
		{"escaped duplicate", strings.Replace(canonical, `"kind":`, `"k\u0069nd":"easynet-lab-result","kind":`, 1), "", "invalid lab input\n", nil},
		{"null", strings.Replace(canonical, `"outputBytes":4`, `"outputBytes":null`, 1), "", "invalid lab input\n", nil},
		{"oversize", canonical + strings.Repeat(" ", 4097-len(canonical)), "", "invalid lab input\n", nil},
		{"second value", canonical + `{}`, "", "invalid lab input\n", nil},
		{"arguments", canonical, "", "invalid lab arguments\n", []string{"fixture-secret"}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			out, diagnostic, err := command(t, 3*time.Second, tc.input, binary, tc.args...)
			if out != tc.output || diagnostic != tc.diagnostic {
				t.Fatalf("unexpected streams: stdout %q stderr %q", out, diagnostic)
			}
			if tc.diagnostic == "" {
				if err != nil {
					t.Fatalf("success exit: %v", err)
				}
			} else {
				var exit *exec.ExitError
				if !errors.As(err, &exit) || exit.ExitCode() != 2 {
					t.Fatalf("expected exit 2: %v", err)
				}
			}
		})
	}
}

func TestCappedWriter(t *testing.T) {
	var w cappedWriter
	if n, err := w.Write(make([]byte, 4096)); n != 4096 || err != nil {
		t.Fatal("writer rejected its exact bound")
	}
	if n, err := w.Write([]byte{1}); n != 0 || err == nil || len(w.data) != 4096 {
		t.Fatal("writer did not retain its bound")
	}
}

type failingReader struct{}

func (failingReader) Read([]byte) (int, error) { return 0, errors.New("fixture-secret") }

type failingWriter struct{ short bool }

func (w failingWriter) Write(p []byte) (int, error) {
	if w.short {
		return len(p) - 1, nil
	}
	return 0, errors.New("fixture-secret")
}

func TestRunIOFailure(t *testing.T) {
	cases := []struct {
		name   string
		input  io.Reader
		output io.Writer
	}{
		{"read", failingReader{}, &bytes.Buffer{}},
		{"write", strings.NewReader(canonical), failingWriter{}},
		{"short write", strings.NewReader(canonical), failingWriter{short: true}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var diagnostic bytes.Buffer
			if code := run(nil, tc.input, tc.output, &diagnostic); code != 2 || diagnostic.String() != "lab I/O failure\n" {
				t.Fatalf("unexpected code/diagnostic: %d %q", code, diagnostic.String())
			}
		})
	}
}
