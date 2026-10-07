package sshlab

import (
	"errors"
	"strings"
	"sync"
	"testing"
)

func TestBridgeOutputFragmentedLines(t *testing.T) {
	w := newBridgeOutput(true)
	for _, chunk := range []string{"rea", "dy\na", "ck\njoined\n"} {
		if n, err := w.Write([]byte(chunk)); err != nil || n != len(chunk) {
			t.Fatal("fragmented write failed")
		}
	}
	if w.Finish() != nil || w.Finish() != nil {
		t.Fatal("finish failed")
	}
	for _, want := range []string{"ready", "ack", "joined"} {
		if got, ok := <-w.Events(); !ok || got != want {
			t.Fatal("fixed event mismatch")
		}
	}
	if _, ok := <-w.Events(); ok {
		t.Fatal("event queue not closed")
	}
	if w.Snapshot().Bytes != len("ready\nack\njoined\n") {
		t.Fatal("incorrect byte count")
	}
	if _, err := w.Write([]byte("ready\n")); !errors.Is(err, ErrBridgeProtocol) {
		t.Fatal("write after finish accepted")
	}
}
func TestBridgeOutputDiagnosticsAndRedaction(t *testing.T) {
	for _, fixed := range []string{"invalid fixture input", "fixture I/O failure", "fixture SSH failure", "fixture cleanup failure"} {
		w := newBridgeOutput(false)
		if w.Events() != nil {
			t.Fatal("stderr has events")
		}
		if _, err := w.Write([]byte(fixed + "\n")); err != nil {
			t.Fatal("fixed diagnostic refused")
		}
		if w.Snapshot().Diagnostic != fixed {
			t.Fatal("fixed diagnostic lost")
		}
		if _, err := w.Write([]byte(fixed + "\n")); !errors.Is(err, ErrBridgeProtocol) {
			t.Fatal("duplicate diagnostic accepted")
		}
		if !errors.Is(w.Finish(), ErrBridgeProtocol) {
			t.Fatal("failure not sticky")
		}
	}
	for _, raw := range []string{"unrecognized payload\n", "\n", "ready\r\n", "ready\x00\n", "\xff\n"} {
		for _, events := range []bool{false, true} {
			w := newBridgeOutput(events)
			if _, err := w.Write([]byte(raw)); !errors.Is(err, ErrBridgeProtocol) {
				t.Fatal("unknown output accepted")
			}
			if s := w.Snapshot(); !s.Failed || s.Diagnostic != "" {
				t.Fatal("raw diagnostic retained")
			}
			if !errors.Is(w.Finish(), ErrBridgeProtocol) {
				t.Fatal("finish changed error")
			}
		}
	}
}
func TestBridgeOutputLimitsAndPartialLine(t *testing.T) {
	for _, input := range []string{strings.Repeat("x", 65), strings.Repeat("x", 4097)} {
		w := newBridgeOutput(true)
		if _, err := w.Write([]byte(input)); !errors.Is(err, ErrBridgeOutputLimit) {
			t.Fatal("size limit not enforced")
		}
		if _, err := w.Write([]byte("ready\n")); !errors.Is(err, ErrBridgeOutputLimit) {
			t.Fatal("limit not sticky")
		}
		if !errors.Is(w.Finish(), ErrBridgeOutputLimit) {
			t.Fatal("finish changed limit")
		}
	}
	w := newBridgeOutput(true)
	if n, err := w.Write([]byte(strings.Repeat("x", 64))); err != nil || n != 64 {
		t.Fatal("partial boundary refused")
	}
	if !errors.Is(w.Finish(), ErrBridgeProtocol) {
		t.Fatal("unfinished partial accepted")
	}
	stdout, stderr := newBridgeOutput(true), newBridgeOutput(false)
	if n, err := stdout.Write(make([]byte, 4097)); n != 0 || !errors.Is(err, ErrBridgeOutputLimit) {
		t.Fatal("oversized chunk retained")
	}
	if stdout.Snapshot().Bytes != 0 {
		t.Fatal("rejected chunk counted")
	}
	if _, err := stderr.Write([]byte("fixture I/O failure\n")); err != nil {
		t.Fatal("stream caps coupled")
	}
	stdout.Finish()
	stderr.Finish()
}
func TestBridgeOutputQueueAndConcurrentWrites(t *testing.T) {
	// Repeated ready lines test the allowlist codec, not valid phase ordering.
	w := newBridgeOutput(true)
	var group sync.WaitGroup
	group.Add(8)
	for i := 0; i < 8; i++ {
		go func() {
			defer group.Done()
			if n, err := w.Write([]byte("ready\n")); n != 6 || err != nil {
				t.Error("concurrent write failed")
			}
			w.Snapshot()
		}()
	}
	group.Wait()
	if _, err := w.Write([]byte("ready\n")); !errors.Is(err, ErrBridgeProtocol) {
		t.Fatal("queue overflow accepted")
	}
	if !errors.Is(w.Finish(), ErrBridgeProtocol) || !errors.Is(w.Finish(), ErrBridgeProtocol) {
		t.Fatal("finish not idempotent")
	}
	count := 0
	for range w.Events() {
		count++
	}
	if count != 8 {
		t.Fatal("queued events lost")
	}
}

func TestBridgeOutputCumulativeBoundary(t *testing.T) {
	w := newBridgeOutput(true)
	for i := 0; i < 682; i++ {
		if _, err := w.Write([]byte("ready\n")); err != nil {
			t.Fatal("live queue write failed")
		}
		if <-w.Events() != "ready" {
			t.Fatal("fixed event mismatch")
		}
	}
	if _, err := w.Write([]byte("ack\n")); err != nil {
		t.Fatal("exact cap refused")
	}
	if <-w.Events() != "ack" {
		t.Fatal("fixed event mismatch")
	}
	if w.Snapshot().Bytes != 4096 {
		t.Fatal("cumulative count incorrect")
	}
	if n, err := w.Write([]byte("x")); n != 0 || !errors.Is(err, ErrBridgeOutputLimit) {
		t.Fatal("cumulative cap exceeded")
	}
	if w.Snapshot().Bytes != 4096 {
		t.Fatal("rejected byte counted")
	}
	if !errors.Is(w.Finish(), ErrBridgeOutputLimit) {
		t.Fatal("limit not sticky")
	}
}
