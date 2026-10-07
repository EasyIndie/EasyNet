//go:build unix && bridgeipc

package sshlab

import (
	"context"
	"errors"
	"net"
	"strconv"
	"testing"
	"time"
)

const bridgeAuthFixtureBinary = "/tmp/easynet-poc-cache/rust-target/debug/ssh_auth_fixture"

func bridgeAuthFixture(t *testing.T, stall bool) *Fixture {
	t.Helper()
	create := NewFixture
	if stall {
		create = NewAuthStallFixture
	}
	f, err := create()
	if err != nil {
		t.Fatal("owned auth fixture setup failed")
	}
	t.Cleanup(func() {
		if f.Close() != nil { // Close releases stalled callbacks and joins workers.
			t.Error("owned auth fixture close failed")
		}
	})
	return f
}

func bridgeAuthFrame(t *testing.T, f, substitute *Fixture, mode string) []byte {
	t.Helper()
	_, portText, err := net.SplitHostPort(f.Endpoint())
	if err != nil {
		t.Fatal("owned auth endpoint invalid")
	}
	port, err := strconv.ParseUint(portText, 10, 16)
	if err != nil {
		t.Fatal("owned auth port invalid")
	}
	keyFixture := f
	if mode == "wrong-client-key" {
		keyFixture = substitute
	}
	private, err := keyFixture.ClientPrivateKeyPEM()
	if err != nil {
		t.Fatal("owned auth key encoding failed")
	}
	defer clear(private)
	host := f.HostKey().Marshal()
	if mode == "host-mismatch" {
		host = substitute.HostKey().Marshal()
	}
	deadline := uint32(3000)
	if mode == "auth-deadline" {
		deadline = 500
	}
	frame, err := EncodeBridgeFrame(BridgeInput{Port: uint16(port), DeadlineMS: deadline,
		Command: 0, OperationID: "fixture-auth", HostKey: host, PrivateKey: private})
	if err != nil {
		t.Fatal("owned auth frame encoding failed")
	}
	return frame
}

func bridgeAuthReached(t *testing.T, f *Fixture) {
	t.Helper()
	timer := time.NewTimer(2 * time.Second)
	defer timer.Stop()
	select {
	case <-f.AuthReached(): // Unsigned public-key probe, not signed auth success.
	case <-timer.C:
		t.Fatal("owned auth callback deadline exceeded")
	}
}

func TestBridgeAuth(t *testing.T) {
	for _, mode := range []string{"signed-success", "wrong-client-key", "host-mismatch",
		"auth-deadline", "auth-cancel", "auth-eof", "invalid-auth-control", "pre-cancel"} {
		t.Run(mode, func(t *testing.T) {
			stall := mode == "auth-deadline" || mode == "auth-cancel" ||
				mode == "auth-eof" || mode == "invalid-auth-control"
			fixture := bridgeAuthFixture(t, stall)
			var substitute *Fixture
			if mode == "wrong-client-key" || mode == "host-mismatch" {
				substitute = bridgeAuthFixture(t, false)
			}
			frame := bridgeAuthFrame(t, fixture, substitute, mode)
			defer clear(frame)
			child, err := StartBridgeChild(context.Background(), bridgeAuthFixtureBinary, frame)
			clear(frame)
			if err != nil {
				t.Fatal("owned auth child start failed")
			}
			// LIFO: cancel/reap child before closing either owned server fixture.
			t.Cleanup(func() { _ = child.Close() })
			bridgeReady(t, child)
			if mode == "pre-cancel" {
				if child.Control('C') != nil {
					t.Fatal("fixed auth pre-cancel failed")
				}
			} else {
				if child.Control('G') != nil {
					t.Fatal("fixed auth start failed")
				}
				if stall {
					bridgeAuthReached(t, fixture)
				}
				switch mode {
				case "auth-cancel":
					if child.Control('C') != nil {
						t.Fatal("fixed auth cancellation failed")
					}
				case "auth-eof":
					if child.CloseControl() != nil {
						t.Fatal("fixed auth EOF failed")
					}
				case "invalid-auth-control":
					// Negative input only: bypass parent Control on this owned IPC.
					if child.conn.SetWriteDeadline(time.Now().Add(time.Second)) != nil {
						t.Fatal("owned negative IPC deadline failed")
					}
					if n, err := child.conn.Write([]byte{'X'}); err != nil || n != 1 {
						t.Fatal("owned negative IPC write failed")
					}
				}
			}
			result := bridgeWait(t, child)
			diagnostic := ""
			if mode == "wrong-client-key" || mode == "host-mismatch" || mode == "auth-deadline" {
				diagnostic = "fixture SSH failure"
			} else if mode == "invalid-auth-control" {
				diagnostic = "fixture I/O failure"
			}
			if diagnostic != "" {
				if !errors.Is(result.err, ErrBridgeChildIO) || result.summary.ExitCode != 2 || result.summary.Diagnostic != diagnostic {
					t.Fatal("fixed auth failure summary invalid")
				}
			} else if result.err != nil || result.summary.ExitCode != 0 || result.summary.Diagnostic != "" {
				t.Fatal("auth stage success summary invalid")
			}
			events := []string{"not-dispatched", "joined"}
			if mode == "signed-success" {
				// Reviewed AuthResult::success() is the signed-success evidence.
				events = []string{"authenticated", "not-dispatched", "joined"}
			}
			bridgeRemainingEvents(t, child, events)
			if result.summary.StdoutBytes > 4096 || result.summary.StderrBytes > 4096 {
				t.Fatal("auth output cap exceeded")
			}
			if _, err := child.conn.Write([]byte{'G'}); !errors.Is(err, net.ErrClosed) {
				t.Fatal("owned auth parent descriptor not closed")
			}
			if replay, err := child.Wait(); replay != result.summary || err != result.err {
				t.Fatal("immutable auth wait result differs")
			}
			stats := fixture.Stats()
			if stats.ExecAttempts != 0 || stats.Commands != 0 {
				t.Fatal("auth stage attempted exec")
			}
			if mode == "host-mismatch" || mode == "pre-cancel" {
				if stats.AuthCallbacks != 0 {
					t.Fatal("auth refusal contacted callback")
				}
			} else if stats.AuthCallbacks < 1 {
				t.Fatal("auth callback not observed")
			}
			if substitute != nil && substitute.Stats() != (FixtureStats{}) {
				t.Fatal("substitute fixture contacted")
			}
			if stall {
				select {
				case <-fixture.done:
					t.Fatal("client interruption closed server fixture")
				default: // Server callback waits for fixture Close, not client cancel.
				}
			}
		})
	}
}
