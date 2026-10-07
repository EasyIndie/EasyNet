//go:build unix && bridgeipc

package sshlab

import (
	"context"
	"errors"
	"net"
	"strconv"
	"sync"
	"testing"
	"time"
)

const bridgeFixtureBinary = "/tmp/easynet-poc-cache/rust-target/debug/ssh_fixture"

func bridgeFixtureFrame(t *testing.T, deadline uint32) (*Fixture, []byte) {
	t.Helper()
	f, err := NewFixture()
	if err != nil {
		t.Fatal("owned fixture setup failed")
	}
	t.Cleanup(func() {
		if f.Close() != nil {
			t.Error("owned fixture close failed")
		}
	})
	_, portText, err := net.SplitHostPort(f.Endpoint())
	if err != nil {
		t.Fatal("owned fixture endpoint invalid")
	}
	port, err := strconv.ParseUint(portText, 10, 16)
	if err != nil {
		t.Fatal("owned fixture port invalid")
	}
	private, err := f.ClientPrivateKeyPEM()
	if err != nil {
		t.Fatal("fixture key encoding failed")
	}
	defer clear(private)
	frame, err := EncodeBridgeFrame(BridgeInput{Port: uint16(port), DeadlineMS: deadline,
		OperationID: "fixture-ipc", HostKey: f.HostKey().Marshal(), PrivateKey: private})
	if err != nil {
		t.Fatal("fixture framing failed")
	}
	return f, frame
}
func bridgeReady(t *testing.T, child *BridgeChild) {
	t.Helper()
	timer := time.NewTimer(2 * time.Second)
	defer timer.Stop()
	select {
	case event, ok := <-child.Events():
		if !ok || event != "ready" {
			t.Fatal("expected fixed ready event")
		}
	case <-timer.C:
		t.Fatal("ready deadline exceeded")
	}
}

type bridgeWaitResult struct {
	summary BridgeChildSummary
	err     error
}

func bridgeWait(t *testing.T, child *BridgeChild) bridgeWaitResult {
	t.Helper()
	done := make(chan bridgeWaitResult, 1)
	go func() { s, err := child.Wait(); done <- bridgeWaitResult{s, err} }()
	timer := time.NewTimer(6 * time.Second)
	defer timer.Stop()
	select {
	case result := <-done:
		return result
	case <-timer.C:
		t.Fatal("owned child wait deadline exceeded")
	}
	return bridgeWaitResult{}
}
func bridgeRemainingEvents(t *testing.T, child *BridgeChild, expected []string) {
	t.Helper()
	timer := time.NewTimer(2 * time.Second)
	defer timer.Stop()
	index := 0
	for {
		select {
		case event, ok := <-child.Events():
			if !ok {
				if index != len(expected) {
					t.Fatal("fixed event sequence incomplete")
				}
				return
			}
			if index >= len(expected) || event != expected[index] {
				t.Fatal("unexpected fixed event sequence")
			}
			index++
		case <-timer.C:
			t.Fatal("event close deadline exceeded")
		}
	}
}

func TestBridgeChildIPCLifecycle(t *testing.T) {
	for _, mode := range []string{"go-cancel", "cancel-first", "control-eof", "malformed", "deadline", "context-cancel", "invalid-control"} {
		t.Run(mode, func(t *testing.T) {
			deadline := uint32(3000)
			if mode == "deadline" {
				deadline = 100
			}
			fixture, frame := bridgeFixtureFrame(t, deadline)
			if mode == "malformed" {
				frame = frame[:5]
			}
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			child, err := StartBridgeChild(ctx, bridgeFixtureBinary, frame)
			if err != nil {
				t.Fatal("owned child start failed")
			}
			t.Cleanup(func() { child.Close() })
			if mode != "malformed" {
				bridgeReady(t, child)
			}
			success := mode == "go-cancel" || mode == "cancel-first" || mode == "control-eof"
			switch mode {
			case "go-cancel":
				if child.Control('G') != nil || child.Control('C') != nil {
					t.Fatal("fixed controls failed")
				}
			case "cancel-first":
				if child.Control('C') != nil {
					t.Fatal("fixed cancellation failed")
				}
			case "control-eof":
				if child.CloseControl() != nil {
					t.Fatal("control EOF failed")
				}
			case "context-cancel":
				cancel()
			case "invalid-control":
				if !errors.Is(child.Control('X'), ErrBridgeProtocol) {
					t.Fatal("invalid control accepted")
				}
			}
			result := bridgeWait(t, child)
			if success {
				if result.err != nil || result.summary.ExitCode != 0 || result.summary.Diagnostic != "" {
					t.Fatal("IPC success summary invalid")
				}
				bridgeRemainingEvents(t, child, []string{"not-dispatched", "joined"})
			} else {
				if !errors.Is(result.err, ErrBridgeChildIO) || result.summary.ExitCode == 0 {
					t.Fatal("child failure not observed")
				}
				diagnostic := ""
				if mode == "malformed" {
					diagnostic = "invalid fixture input"
				}
				if mode == "deadline" {
					diagnostic = "fixture I/O failure"
				}
				if result.summary.Diagnostic != diagnostic {
					t.Fatal("fixed diagnostic mismatch")
				}
				if mode == "malformed" && result.summary.StdoutBytes != 0 {
					t.Fatal("malformed frame emitted event")
				}
				bridgeRemainingEvents(t, child, nil)
			}
			if result.summary.StdoutBytes > 4096 || result.summary.StderrBytes > 4096 {
				t.Fatal("output cap exceeded")
			}
			if _, err := child.conn.Write([]byte{'G'}); !errors.Is(err, net.ErrClosed) {
				t.Fatal("owned parent descriptor not closed")
			}
			if stats := fixture.Stats(); stats != (FixtureStats{}) {
				t.Fatal("IPC bootstrap contacted SSH fixture")
			}
			if mode == "go-cancel" {
				var group sync.WaitGroup
				group.Add(8)
				for i := 0; i < 8; i++ {
					go func() {
						defer group.Done()
						s, err := child.Wait()
						if s != result.summary || err != result.err {
							t.Error("immutable wait result differs")
						}
					}()
				}
				group.Wait()
				if child.Close() != nil || child.Close() != nil {
					t.Fatal("successful close not idempotent")
				}
			}
		})
	}
}
