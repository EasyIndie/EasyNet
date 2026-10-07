//go:build unix && bridgeipc

package sshlab

import (
	"context"
	"encoding/binary"
	"errors"
	"net"
	"testing"
	"time"
)

func bridgeFaultPhase(t *testing.T, phase <-chan struct{}) {
	t.Helper()
	timer := time.NewTimer(2 * time.Second)
	defer timer.Stop()
	select {
	case <-phase:
	case <-timer.C:
		t.Fatal("owned fault phase deadline exceeded")
	}
}

func TestBridgeCommandFault(t *testing.T) {
	cases := []struct {
		name           string
		mode           CommandFault
		interrupt      byte
		deadline, ack  bool
		exec, commands int
	}{
		{"channel-deadline", ChannelOpenStall, 0, true, false, 0, 0},
		{"channel-cancel", ChannelOpenStall, 'C', false, false, 0, 0},
		{"channel-eof", ChannelOpenStall, 'E', false, false, 0, 0},
		{"ack-deadline", ExecAckStall, 0, true, false, 1, 0},
		{"ack-cancel", ExecAckStall, 'C', false, false, 1, 0},
		{"ack-eof", ExecAckStall, 'E', false, false, 1, 0},
		{"acklost-cancel", AckLost, 'C', false, false, 1, 1},
		{"acklost-eof", AckLost, 'E', false, false, 1, 1},
		{"no-status", NoStatus, 0, false, true, 1, 1},
		{"nonzero-status", NonzeroStatus, 0, false, true, 1, 1},
		{"no-close-deadline", NoClose, 0, true, true, 1, 1},
		{"invalid-command-control", NoClose, 'X', false, true, 1, 1},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			fixture, err := NewCommandFaultFixture(tc.mode)
			if err != nil {
				t.Fatal("owned command fault setup failed")
			}
			t.Cleanup(func() { _ = fixture.Close() })
			frame := bridgeAuthFrame(t, fixture, nil, "signed-success")
			defer clear(frame)
			if tc.mode == AckLost {
				frame[12] = 1
			}
			if tc.deadline {
				binary.BigEndian.PutUint32(frame[8:12], 500)
			}
			child, err := StartBridgeChild(context.Background(), bridgeCommandFixtureBinary, frame)
			clear(frame)
			if err != nil {
				t.Fatal("owned command fault child start failed")
			}
			t.Cleanup(func() { _ = child.Close() })
			bridgeReady(t, child)
			if child.Control('G') != nil {
				t.Fatal("command fault start failed")
			}
			bridgeCommandEvent(t, child, "authenticated")
			if tc.ack {
				bridgeCommandEvent(t, child, "ack")
			}
			stalled := tc.mode == ChannelOpenStall || tc.mode == ExecAckStall || tc.mode == NoClose || tc.mode == AckLost
			if tc.mode == AckLost {
				bridgeBlockReached(t, fixture)
			} else if stalled {
				bridgeFaultPhase(t, fixture.PhaseReached())
			}
			switch tc.interrupt {
			case 'C':
				if child.Control('C') != nil {
					t.Fatal("command fault cancellation failed")
				}
			case 'E':
				if child.CloseControl() != nil {
					t.Fatal("command fault EOF failed")
				}
			case 'X':
				// One fixed negative byte on this child's owned IPC, not parent Control.
				if child.conn.SetWriteDeadline(time.Now().Add(time.Second)) != nil {
					t.Fatal("negative command IPC deadline failed")
				}
				if n, err := child.conn.Write([]byte{'X'}); n != 1 || err != nil {
					t.Fatal("negative command IPC write failed")
				}
			}
			result := bridgeWait(t, child)
			diagnostic := "fixture SSH failure"
			if tc.interrupt == 'X' {
				diagnostic = "fixture I/O failure"
			}
			if !errors.Is(result.err, ErrBridgeChildIO) || result.summary.ExitCode != 2 || result.summary.Diagnostic != diagnostic {
				t.Fatal("fixed command fault failure summary invalid")
			}
			terminal := "unknown"
			if tc.mode == ChannelOpenStall {
				terminal = "not-dispatched"
			}
			bridgeRemainingEvents(t, child, []string{terminal, "joined"})
			if result.summary.StdoutBytes > 4096 || result.summary.StderrBytes > 4096 {
				t.Fatal("command fault IPC cap exceeded")
			}
			if _, err := child.conn.Write([]byte{'G'}); !errors.Is(err, net.ErrClosed) {
				t.Fatal("command fault descriptor not closed")
			}
			if replay, err := child.Wait(); replay != result.summary || err != result.err {
				t.Fatal("command fault immutable wait differs")
			}
			stats := fixture.Stats()
			if stats.AuthCallbacks < 1 || stats.ExecAttempts != tc.exec || stats.Commands != tc.commands {
				t.Fatal("command fault dispatch counters invalid")
			}
			pending := 0
			if tc.mode == AckLost {
				pending = 1
			}
			if fixture.PendingBlocks() != pending {
				t.Fatal("command fault remote pending state invalid")
			}
			if stalled {
				select {
				case <-fixture.done:
					t.Fatal("command fault interruption closed server fixture")
				default:
				}
			}
			if fixture.Close() != nil || fixture.PendingBlocks() != 0 {
				t.Fatal("command fault owned server cleanup failed")
			}
		})
	}
}
