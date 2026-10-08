//go:build darwin && rustvault

package sshlab

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
	"testing"
	"time"
)

const rustVaultHelper = "/tmp/easynet-poc-cache/rust-vault/vault_fixture"
const rustVaultHash = "1c57903b4d86ea44ba6443de9b5b8c1f78b6d6fdb7e3f6d13e4228f8b1ac29fd"

var rustVaultChecks = []string{
	"password_generated", "create_guard", "creation_metadata_unchanged", "unlock_native",
	"unlocked_confirmed", "add", "read_initial_checked", "update", "read_updated_checked",
	"delete", "deleted_absent", "readd", "read_readded_checked", "lock_native",
	"locked_confirmed", "locked_read_queried", "locked_read_rejected", "final_metadata_unchanged",
	"create_wrapper_present", "create_keychain_ref_present", "locked_read_data_returned",
}
var rustVaultStages = []string{
	"create_guard", "unlock_native", "unlock_state_native", "add", "read_initial_checked",
	"update", "read_updated_checked", "delete", "deleted_read_native", "readd",
	"read_readded_checked", "lock_native", "lock_state_native", "locked_read_native", "final_metadata",
}

type rustVaultOutput struct {
	data     bytes.Buffer
	overflow bool
}

func (b *rustVaultOutput) Write(p []byte) (int, error) {
	n := len(p)
	if remaining := 4096 - b.data.Len(); len(p) > remaining {
		b.overflow = true
		p = p[:remaining]
	}
	_, _ = b.data.Write(p)
	return n, nil // No ReaderFrom: all bytes pass through the cap, without blocking child pipes.
}

type rustVaultReport struct {
	outcome  string
	checks   map[string]bool
	statuses map[string]int32
}

func rustVaultObject(t *testing.T, data []byte, allowed []string) map[string]json.RawMessage {
	t.Helper()
	d := json.NewDecoder(bytes.NewReader(data))
	token, err := d.Token()
	if err != nil || token != json.Delim('{') {
		t.Fatal("invalid report object")
	}
	result := map[string]json.RawMessage{}
	for d.More() {
		token, err = d.Token()
		key, ok := token.(string)
		known := false
		for _, candidate := range allowed {
			if key == candidate {
				known = true
			}
		}
		if err != nil || !ok || !known {
			t.Fatal("unknown report field")
		}
		if _, duplicate := result[key]; duplicate {
			t.Fatal("duplicate report field")
		}
		var value json.RawMessage
		if d.Decode(&value) != nil || bytes.Equal(bytes.TrimSpace(value), []byte("null")) {
			t.Fatal("invalid or null report value")
		}
		result[key] = value
	}
	token, err = d.Token()
	if err != nil || token != json.Delim('}') || d.Decode(new(any)) != io.EOF {
		t.Fatal("invalid report ending")
	}
	return result
}
func rustVaultDecode(t *testing.T, data []byte) rustVaultReport {
	t.Helper()
	outer := rustVaultObject(t, data, []string{"outcome", "checks", "statuses"})
	if len(outer) != 3 {
		t.Fatal("missing outer report field")
	}
	r := rustVaultReport{checks: map[string]bool{}, statuses: map[string]int32{}}
	if json.Unmarshal(outer["outcome"], &r.outcome) != nil || (r.outcome != "pass" && r.outcome != "blocked" && r.outcome != "rejected") {
		t.Fatal("invalid report outcome")
	}
	checks := rustVaultObject(t, outer["checks"], rustVaultChecks)
	if len(checks) != len(rustVaultChecks) {
		t.Fatal("missing report check")
	}
	for key, raw := range checks {
		var value bool
		if json.Unmarshal(raw, &value) != nil {
			t.Fatal("nonboolean report check")
		}
		r.checks[key] = value
	}
	for key, raw := range rustVaultObject(t, outer["statuses"], rustVaultStages) {
		var value int32
		if json.Unmarshal(raw, &value) != nil {
			t.Fatal("nonint32 report status")
		}
		r.statuses[key] = value
	}
	return r
}

func rustVaultVerifyHelper(t *testing.T) {
	t.Helper()
	for _, path := range []string{"/tmp/easynet-poc-cache", "/tmp/easynet-poc-cache/rust-vault", rustVaultHelper} {
		info, err := os.Lstat(path)
		if err != nil {
			t.Fatal("helper trust metadata unavailable")
		}
		stat, ok := info.Sys().(*syscall.Stat_t)
		if !ok || stat.Uid != uint32(os.Geteuid()) || info.Mode().Perm()&0022 != 0 {
			t.Fatal("helper ownership or write guard failed")
		}
		if path != rustVaultHelper {
			if !info.IsDir() {
				t.Fatal("helper parent is not a nonsymlink directory")
			}
		} else if !info.Mode().IsRegular() || info.Mode().Perm()&0111 == 0 || info.Size() > 64<<20 {
			t.Fatal("helper file guard failed")
		}
	}
	file, err := os.Open(rustVaultHelper)
	if err != nil {
		t.Fatal("helper hash open failed")
	}
	sum := sha256.New()
	n, readErr := io.Copy(sum, io.LimitReader(file, (64<<20)+1))
	closeErr := file.Close()
	if readErr != nil || closeErr != nil || n > 64<<20 || hex.EncodeToString(sum.Sum(nil)) != rustVaultHash {
		t.Fatal("helper hash guard failed")
	}
}

func TestRustNativeVaultIsolated(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Fatal("non-root fixture execution required")
	}
	owned := func(t *testing.T, prefixes ...string) string {
		t.Helper()
		prefix := "easynet-vault-lab-"
		if len(prefixes) != 0 {
			prefix = prefixes[0]
		}
		dir, err := os.MkdirTemp("/tmp", prefix)
		if err != nil {
			t.Fatal("owned directory creation failed")
		}
		t.Cleanup(func() {
			// Only these exact MkdirTemp paths are removed; every Run has already joined.
			if os.RemoveAll(dir) != nil {
				t.Error("owned directory cleanup failed")
			}
			if _, err := os.Lstat(dir); !os.IsNotExist(err) {
				t.Error("owned directory cleanup unverified")
			}
		})
		info, err := os.Lstat(dir)
		if err != nil {
			t.Fatal("owned directory metadata unavailable")
		}
		stat, ok := info.Sys().(*syscall.Stat_t)
		if !ok || stat.Uid != uint32(os.Geteuid()) || !info.IsDir() || info.Mode().Perm() != 0700 || filepath.Dir(dir) != "/tmp" {
			t.Fatal("owned directory guard failed")
		}
		return dir
	}
	observe := func(t *testing.T, args ...string) (rustVaultReport, int) {
		t.Helper()
		rustVaultVerifyHelper(t) // Recheck both private parents and pinned bytes for each launch.
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		cmd := exec.CommandContext(ctx, rustVaultHelper, args...)
		cmd.WaitDelay = time.Second
		out, diagnostic := &rustVaultOutput{}, &rustVaultOutput{}
		cmd.Stdout, cmd.Stderr = out, diagnostic
		err := cmd.Run() // Reaps the child and joins pipe writers before owned cleanup.
		if ctx.Err() != nil || out.overflow || diagnostic.overflow || diagnostic.data.Len() != 0 {
			t.Fatal("helper deadline or output guard failed")
		}
		code := 0
		if err != nil {
			exit, ok := err.(*exec.ExitError)
			if !ok {
				t.Fatal("helper launch or wait failed")
			}
			code = exit.ExitCode()
		}
		r := rustVaultDecode(t, out.data.Bytes())
		for _, key := range rustVaultStages {
			if status, present := r.statuses[key]; present {
				t.Logf("%s=%d", key, status)
			}
		}
		return r, code
	}
	if !t.Run("empty_arguments", func(t *testing.T) {
		r, code := observe(t)
		if code != 1 || r.outcome != "rejected" || len(r.statuses) != 0 {
			t.Fatal("empty arguments not rejected")
		}
		for _, value := range r.checks {
			if value {
				t.Fatal("rejected report claimed work")
			}
		}
	}) {
		return
	}
	for _, name := range []string{"bad_prefix", "mode_0755", "owned_symlink"} {
		if !t.Run(name, func(t *testing.T) {
			dir := owned(t)
			argument := dir
			switch name {
			case "bad_prefix":
				argument = owned(t, "easynet-vault-invalid-")
			case "mode_0755":
				if os.Chmod(dir, 0755) != nil {
					t.Fatal("negative fixture mode failed")
				}
			case "owned_symlink":
				target := owned(t)
				if os.Remove(dir) != nil || os.Symlink(target, dir) != nil {
					t.Fatal("negative symlink fixture failed")
				}
			}
			r, code := observe(t, argument)
			if code != 1 || r.outcome != "blocked" || len(r.statuses) != 2 || r.statuses["create_guard"] != -50 || r.statuses["final_metadata"] != -50 {
				t.Fatal("unsafe path status evidence failed")
			}
			for key, value := range r.checks {
				if value != (key == "password_generated") {
					t.Fatal("unsafe path check evidence failed")
				}
			}
			if _, err := os.Lstat(filepath.Join(argument, "fixture.keychain")); !os.IsNotExist(err) {
				t.Fatal("negative fixture unexpectedly created")
			}
		}) {
			return
		}
	}
	t.Run("scoped_crud_and_locked_read", func(t *testing.T) {
		r, code := observe(t, owned(t))
		if code != 0 || r.outcome != "pass" || len(r.statuses) != len(rustVaultStages) {
			t.Fatal("native fixture refused or failed")
		}
		for i, key := range rustVaultChecks {
			if r.checks[key] != (i < 20) {
				t.Fatal("required native check or diagnostic failed")
			}
		}
		for _, key := range rustVaultStages {
			status, present := r.statuses[key]
			if !present || (key == "locked_read_native" && status == 0) || (key == "deleted_read_native" && status != -25300) || (key != "locked_read_native" && key != "deleted_read_native" && status != 0) {
				t.Fatal("native status evidence failed")
			}
		}
		t.Log("18 required native checks and 15 bounded statuses verified")
	})
}
