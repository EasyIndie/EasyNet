package main

/*
#cgo LDFLAGS: -framework Security -framework CoreFoundation
#include "native.h"
#include <stdlib.h>
*/
import "C"

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"unsafe"
)

type report struct {
	Outcome  string          `json:"outcome"`
	Statuses map[string]int  `json:"statuses"`
	Checks   map[string]bool `json:"checks"`
}

var requiredChecks = []string{
	"password_generated", "create_guard", "creation_metadata_unchanged", "unlock_native", "unlocked_confirmed",
	"add", "read_initial_checked", "update", "read_updated_checked", "delete", "deleted_absent",
	"readd", "read_readded_checked", "lock_native", "locked_confirmed", "locked_read_queried", "locked_read_rejected", "final_metadata_unchanged",
}

func newReport() report {
	result := report{Outcome: "rejected", Statuses: map[string]int{}, Checks: map[string]bool{}}
	for _, check := range requiredChecks {
		result.Checks[check] = false
	}
	return result
}
func run(directory string) (result report) {
	result = newReport()
	if directory == "" || strings.ContainsRune(directory, 0) {
		return
	}
	result.Outcome = "blocked"
	raw, password := make([]byte, 32), make([]byte, 64)
	first, second := []byte("fixture-one"), []byte("fixture-two")
	defer func() { clear(raw); clear(password); clear(first); clear(second) }()
	if _, err := rand.Read(raw); err != nil {
		return
	}
	hex.Encode(password, raw)
	clear(raw)
	result.Checks["password_generated"] = true
	path := C.CString(filepath.Join(directory, "fixture.keychain"))
	if path == nil {
		return
	}
	defer C.free(unsafe.Pointer(path))
	var vault *C.Vault
	var unchanged C.bool
	status := C.vault_create(path, unsafe.Pointer(&password[0]), C.UInt32(len(password)), &vault, &unchanged)
	result.Checks["create_handle_present"] = vault != nil
	defer func() {
		defer C.vault_release(vault)
		var final C.bool
		finalStatus := C.vault_unchanged(vault, &final)
		result.Statuses["final_metadata"] = int(finalStatus)
		result.Checks["final_metadata_unchanged"] = finalStatus == 0 && bool(final)
		for _, check := range requiredChecks {
			if !result.Checks[check] {
				return
			}
		}
		result.Outcome = "pass"
	}()
	ok := func(stage string, status C.OSStatus) bool {
		result.Statuses[stage] = int(status)
		result.Checks[stage] = status == 0
		return status == 0
	}
	result.Checks["creation_metadata_unchanged"] = bool(unchanged)
	if !ok("create_guard", status) || !bool(unchanged) {
		return
	}
	if !ok("unlock_native", C.vault_unlock(vault, unsafe.Pointer(&password[0]), C.UInt32(len(password)))) {
		return
	}
	var unlocked C.bool
	status = C.vault_is_unlocked(vault, &unlocked)
	result.Statuses["unlock_state_native"] = int(status)
	result.Checks["unlocked_confirmed"] = status == 0 && bool(unlocked)
	if !result.Checks["unlocked_confirmed"] {
		return
	}
	read := func(stage string, expected []byte) bool {
		var equal, returned C.bool
		status := C.vault_read_equals(vault, unsafe.Pointer(&expected[0]), C.UInt32(len(expected)), &equal, &returned)
		result.Statuses[stage] = int(status)
		result.Checks[stage] = status == 0 && bool(equal) && bool(returned)
		return result.Checks[stage]
	}
	if !ok("add", C.vault_add(vault, unsafe.Pointer(&first[0]), C.UInt32(len(first)))) || !read("read_initial_checked", first) {
		return
	}
	if !ok("update", C.vault_update(vault, unsafe.Pointer(&second[0]), C.UInt32(len(second)))) || !read("read_updated_checked", second) {
		return
	}
	if !ok("delete", C.vault_delete(vault)) {
		return
	}
	var returned, queried C.bool
	status = C.vault_read_status(vault, &returned, &queried)
	result.Statuses["deleted_read_native"] = int(status)
	result.Checks["deleted_absent"] = bool(queried) && status == C.errSecItemNotFound && !bool(returned)
	if !result.Checks["deleted_absent"] {
		return
	}
	if !ok("readd", C.vault_add(vault, unsafe.Pointer(&first[0]), C.UInt32(len(first)))) || !read("read_readded_checked", first) {
		return
	}
	if !ok("lock_native", C.vault_lock(vault)) {
		return
	}
	status = C.vault_is_unlocked(vault, &unlocked)
	result.Statuses["lock_state_native"] = int(status)
	result.Checks["locked_confirmed"] = status == 0 && !bool(unlocked)
	if !result.Checks["locked_confirmed"] {
		return
	}
	status = C.vault_read_status(vault, &returned, &queried)
	result.Statuses["locked_read_native"] = int(status)
	result.Checks["locked_read_queried"] = bool(queried)
	result.Checks["locked_read_data_returned"] = bool(returned)
	result.Checks["locked_read_rejected"] = bool(queried) && status != 0 && !bool(returned)
	return
}
func main() {
	result := newReport()
	if len(os.Args) == 2 {
		result = run(os.Args[1])
	}
	if err := json.NewEncoder(os.Stdout).Encode(result); err != nil {
		os.Exit(1)
	}
	if result.Outcome != "pass" {
		os.Exit(1)
	}
}
