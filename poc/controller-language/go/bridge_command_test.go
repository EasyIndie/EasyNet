//go:build unix && bridgeipc

package sshlab

import (
	"context"
	"errors"
	"net"
	"testing"
	"time"
)

const bridgeCommandFixtureBinary = "/tmp/easynet-poc-cache/rust-target/debug/ssh_command_fixture"

func bridgeCommandEvent(t *testing.T, child *BridgeChild, expected string) {
	t.Helper()
	timer := time.NewTimer(2 * time.Second)
	defer timer.Stop()
	select {
	case event, ok := <-child.Events():
		if !ok || event != expected {
			t.Fatal("fixed command phase event invalid")
		}
	case <-timer.C:
		t.Fatal("owned command phase deadline exceeded")
	}
}
func bridgeBlockReached(t *testing.T, fixture *Fixture) {
	t.Helper()
	timer := time.NewTimer(2 * time.Second)
	defer timer.Stop()
	select {
	case <-fixture.BlockReached():
	case <-timer.C:
		t.Fatal("owned block fixture deadline exceeded")
	}
}

func TestBridgeCommand(t *testing.T) {
	for _, mode := range []string{"complete", "output-overflow", "block-deadline", "block-cancel", "block-eof", "pre-cancel"} {
		t.Run(mode, func(t *testing.T) {
			deadline := uint32(3000)
			if mode == "block-deadline" {
				deadline = 500
			}
			fixture, frame := bridgeFixtureFrame(t, deadline)
			// Reviewed frame header: command byte12 only. Credentials remain in memory.
			switch mode {
			case "complete":
				frame[12] = 0
			case "output-overflow":
				frame[12] = 2
			default:
				frame[12] = 1
			}
			defer clear(frame)
			child, err := StartBridgeChild(context.Background(), bridgeCommandFixtureBinary, frame)
			clear(frame)
			if err != nil {
				t.Fatal("owned command child start failed")
			}
			t.Cleanup(func() { _ = child.Close() }) // LIFO: reap before server Close.
			bridgeReady(t, child)
			if mode == "pre-cancel" {
				if child.Control('C') != nil {
					t.Fatal("command pre-cancel failed")
				}
			} else {
				if child.Control('G') != nil {
					t.Fatal("command start failed")
				}
				bridgeCommandEvent(t, child, "authenticated")
				bridgeCommandEvent(t, child, "ack") // Actual Success, not exec enqueue.
				if mode == "block-deadline" || mode == "block-cancel" || mode == "block-eof" {
					bridgeBlockReached(t, fixture)
				}
				switch mode {
				case "block-cancel":
					if child.Control('C') != nil {
						t.Fatal("command cancellation failed")
					}
				case "block-eof":
					if child.CloseControl() != nil {
						t.Fatal("command EOF failed")
					}
				}
			}
			result := bridgeWait(t, child)
			if mode == "output-overflow" || mode == "block-deadline" {
				if !errors.Is(result.err, ErrBridgeChildIO) || result.summary.ExitCode != 2 || result.summary.Diagnostic != "fixture SSH failure" {
					t.Fatal("fixed command failure summary invalid")
				}
			} else if result.err != nil || result.summary.ExitCode != 0 || result.summary.Diagnostic != "" {
				t.Fatal("command stage containment summary invalid")
			}
			terminal := "unknown"
			if mode == "complete" {
				terminal = "fixture-complete-observed"
			}
			if mode == "pre-cancel" {
				terminal = "not-dispatched"
			}
			bridgeRemainingEvents(t, child, []string{terminal, "joined"})
			if result.summary.StdoutBytes > 4096 || result.summary.StderrBytes > 4096 {
				t.Fatal("command IPC output cap exceeded")
			}
			if _, err := child.conn.Write([]byte{'G'}); !errors.Is(err, net.ErrClosed) {
				t.Fatal("owned command parent descriptor not closed")
			}
			if replay, err := child.Wait(); replay != result.summary || err != result.err {
				t.Fatal("immutable command wait result differs")
			}
			stats := fixture.Stats()
			if mode == "pre-cancel" {
				if stats != (FixtureStats{}) {
					t.Fatal("pre-cancel contacted fixture")
				}
			} else if stats.AuthCallbacks < 1 || stats.ExecAttempts != 1 || stats.Commands != 1 {
				t.Fatal("command fixture dispatch count invalid")
			}
			if mode == "block-deadline" || mode == "block-cancel" || mode == "block-eof" {
				if fixture.PendingBlocks() != 1 {
					t.Fatal("client interruption lost remote pending state")
				}
				select {
				case <-fixture.done:
					t.Fatal("client interruption closed remote fixture")
				default:
				}
				if fixture.Close() != nil || fixture.PendingBlocks() != 0 {
					t.Fatal("owned server cleanup failed to release and join pending block")
				}
			}
		})
	}
}
