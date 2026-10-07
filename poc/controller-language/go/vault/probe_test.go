//go:build nativeprobe

package main

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"
)

type probeOutput struct {
	buffer   bytes.Buffer
	limit    int
	overflow bool
}

func (b *probeOutput) Write(p []byte) (int, error) {
	n := len(p)
	if remaining := b.limit - b.buffer.Len(); len(p) > remaining {
		b.overflow = true
		p = p[:remaining]
	}
	_, _ = b.buffer.Write(p)
	return n, nil
}
func TestNativeProbeIsolated(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Fatal("non-root fixture execution required")
	}
	dir, err := os.MkdirTemp("/tmp", "easynet-vault-lab-")
	if err != nil {
		t.Fatal("owned directory creation failed")
	}
	t.Cleanup(func() {
		// Every cmd.Run below has joined before cleanup of this recorded path.
		if os.RemoveAll(dir) != nil {
			t.Error("owned directory cleanup failed")
		}
		if _, err := os.Lstat(dir); !os.IsNotExist(err) {
			t.Error("owned directory cleanup unverified")
		}
	})
	info, err := os.Lstat(dir)
	if err != nil || !info.IsDir() || info.Mode().Perm() != 0700 {
		t.Fatal("owned directory guard failed")
	}
	run := func(timeout time.Duration, limit int, name string, args ...string) []byte {
		ctx, cancel := context.WithTimeout(context.Background(), timeout)
		defer cancel()
		cmd := exec.CommandContext(ctx, name, args...)
		cmd.WaitDelay = time.Second
		out, diagnostic := &probeOutput{limit: limit}, &probeOutput{limit: limit}
		cmd.Stdout, cmd.Stderr = out, diagnostic
		err := cmd.Run()
		if ctx.Err() != nil || out.overflow || diagnostic.overflow {
			t.Fatal("bounded process timeout or output overflow")
		}
		if err != nil {
			t.Fatal("bounded process launch, wait or exit failed")
		}
		if limit == 4096 && diagnostic.buffer.Len() != 0 {
			t.Fatal("unexpected probe diagnostic data")
		}
		return out.buffer.Bytes()
	}
	helper := filepath.Join(dir, "helper")
	run(15*time.Second, 65536, "/tmp/easynet-poc-toolchains/go/bin/go", "build", "-o", helper, ".")
	data := run(10*time.Second, 4096, helper, "--probe", dir)
	// Pointers reject missing/null fields; the decoder rejects unknown outer fields.
	var result struct {
		PathGuardOK *bool `json:"path_guard_ok"`
		Stage       *int  `json:"stage"`
		Status      *int  `json:"status"`
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if decoder.Decode(&result) != nil || decoder.Decode(new(any)) != io.EOF || result.PathGuardOK == nil || result.Stage == nil || result.Status == nil {
		t.Fatal("malformed probe report")
	}
	stage, status, guard := *result.Stage, *result.Status, *result.PathGuardOK
	switch stage {
	case 0, 1, 2, 3, 4, 5:
		if guard || status != -50 {
			t.Fatal("inconsistent path diagnostic")
		}
	case 10, 11, 12, 13, 14:
		if !guard || status == 0 {
			t.Fatal("inconsistent metadata diagnostic")
		}
	case 15:
		if !guard || status != 0 {
			t.Fatal("inconsistent snapshot diagnostic")
		}
	default:
		t.Fatal("unknown probe stage")
	}
	if _, err := os.Lstat(filepath.Join(dir, "fixture.keychain")); !os.IsNotExist(err) {
		t.Fatal("probe unexpectedly created fixture")
	}
	t.Logf("stage=%d status=%d path_guard_ok=%t", stage, status, guard)
}
