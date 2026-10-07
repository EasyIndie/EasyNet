//go:build nativevault

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

type cappedOutput struct {
	buffer   bytes.Buffer
	limit    int
	overflow bool
}

func (b *cappedOutput) Write(p []byte) (int, error) {
	n := len(p)
	if remaining := b.limit - b.buffer.Len(); len(p) > remaining {
		b.overflow = true
		p = p[:remaining]
	}
	_, _ = b.buffer.Write(p)
	return n, nil
}

func TestNativeVaultIsolated(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Fatal("non-root fixture execution required")
	}
	owned := func(t *testing.T, prefixes ...string) string {
		prefix := "easynet-vault-lab-"
		if len(prefixes) != 0 {
			prefix = prefixes[0]
		}
		dir, err := os.MkdirTemp("/tmp", prefix)
		if err != nil {
			t.Fatal("owned directory creation failed")
		}
		t.Cleanup(func() {
			if err := os.RemoveAll(dir); err != nil {
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
		return dir
	}
	// Run joins the process and its output goroutines before any cleanup.
	run := func(t *testing.T, timeout time.Duration, cap int, name string, args ...string) ([]byte, int) {
		ctx, cancel := context.WithTimeout(context.Background(), timeout)
		defer cancel()
		cmd := exec.CommandContext(ctx, name, args...)
		cmd.WaitDelay = time.Second
		out, diagnostic := &cappedOutput{limit: cap}, &cappedOutput{limit: cap}
		cmd.Stdout, cmd.Stderr = out, diagnostic
		err := cmd.Run()
		if ctx.Err() != nil || out.overflow || diagnostic.overflow {
			t.Fatal("bounded process timeout or output overflow")
		}
		code := 0
		if err != nil {
			if exit, ok := err.(*exec.ExitError); ok {
				code = exit.ExitCode()
			} else {
				t.Fatal("bounded process launch or wait failed")
			}
		}
		return out.buffer.Bytes(), code
	}
	buildDir := owned(t)
	helper := filepath.Join(buildDir, "helper")
	_, code := run(t, 15*time.Second, 65536, "/tmp/easynet-poc-toolchains/go/bin/go", "build", "-o", helper, ".")
	if code != 0 {
		t.Fatal("helper compilation failed")
	}
	fixedChecks := []string{"password_generated", "create_guard", "creation_metadata_unchanged", "unlock_native", "unlocked_confirmed", "add", "read_initial_checked", "update", "read_updated_checked", "delete", "deleted_absent", "readd", "read_readded_checked", "lock_native", "locked_confirmed", "locked_read_queried", "locked_read_rejected", "final_metadata_unchanged"}
	statusKeys := map[string]bool{}
	for _, key := range []string{"create_guard", "final_metadata", "unlock_native", "unlock_state_native", "add", "read_initial_checked", "update", "read_updated_checked", "delete", "deleted_read_native", "readd", "read_readded_checked", "lock_native", "lock_state_native", "locked_read_native"} {
		statusKeys[key] = true
	}
	checkKeys := map[string]bool{"create_handle_present": true, "locked_read_data_returned": true}
	for _, key := range fixedChecks {
		checkKeys[key] = true
	}
	observe := func(t *testing.T, args ...string) (report, int) {
		data, code := run(t, 10*time.Second, 4096, helper, args...)
		var result report
		decoder := json.NewDecoder(bytes.NewReader(data))
		decoder.DisallowUnknownFields()
		if decoder.Decode(&result) != nil || decoder.Decode(new(any)) != io.EOF {
			t.Fatal("malformed helper report")
		}
		if result.Outcome != "pass" && result.Outcome != "blocked" && result.Outcome != "rejected" {
			t.Fatal("unknown helper outcome")
		}
		for key, status := range result.Statuses {
			if !statusKeys[key] {
				t.Fatal("unknown helper status stage")
			}
			t.Logf("%s=%d", key, status)
		}
		for key := range result.Checks {
			if !checkKeys[key] {
				t.Fatal("unknown helper check")
			}
		}
		for _, key := range fixedChecks {
			if _, present := result.Checks[key]; !present {
				t.Fatal("missing required helper check")
			}
		}
		return result, code
	}
	if !t.Run("empty_arguments", func(t *testing.T) {
		r, code := observe(t)
		if code != 1 || r.Outcome != "rejected" || len(r.Statuses) != 0 || len(r.Checks) != len(fixedChecks) {
			t.Fatal("empty arguments not rejected before native access")
		}
		for _, value := range r.Checks {
			if value {
				t.Fatal("empty arguments reached helper work")
			}
		}
	}) {
		return
	}
	for _, name := range []string{"bad_prefix", "mode_0755", "symlink"} {
		if !t.Run(name, func(t *testing.T) {
			dir := owned(t)
			switch name {
			case "bad_prefix":
				dir = owned(t, "easynet-vault-invalid-")
			case "mode_0755":
				if os.Chmod(dir, 0755) != nil {
					t.Fatal("negative fixture mode failed")
				}
			case "symlink":
				target := owned(t)
				if os.Remove(dir) != nil || os.Symlink(target, dir) != nil {
					t.Fatal("negative symlink fixture failed")
				}
			}
			r, code := observe(t, dir)
			status, hasStatus := r.Statuses["create_guard"]
			handle, hasHandle := r.Checks["create_handle_present"]
			if code != 1 || r.Outcome != "blocked" || !hasStatus || status != -50 || !hasHandle || handle {
				t.Fatal("unsafe path not rejected before native creation")
			}
			if _, err := os.Lstat(filepath.Join(dir, "fixture.keychain")); !os.IsNotExist(err) {
				t.Fatal("negative fixture unexpectedly created")
			}
		}) {
			return
		}
	}
	t.Run("scoped_crud_and_locked_read", func(t *testing.T) {
		r, code := observe(t, owned(t))
		if code != 0 || r.Outcome != "pass" {
			t.Fatal("native fixture refused or failed")
		}
		for _, key := range fixedChecks {
			if !r.Checks[key] {
				t.Fatal("required native check failed")
			}
		}
		returned, hasReturned := r.Checks["locked_read_data_returned"]
		handle, hasHandle := r.Checks["create_handle_present"]
		if !hasReturned || returned || !hasHandle || !handle {
			t.Fatal("native handle or locked data observation failed")
		}
		for key := range statusKeys {
			status, present := r.Statuses[key]
			if !present || (key == "locked_read_native" && status == 0) || (key == "deleted_read_native" && status != -25300) || (key != "locked_read_native" && key != "deleted_read_native" && status != 0) {
				t.Fatal("native status evidence failed")
			}
		}
		t.Logf("locked_read_native=%d; locked_read_data_returned=false", r.Statuses["locked_read_native"])
	})
}
