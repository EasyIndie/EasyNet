//go:build unix && bridgeipc

package sshlab

import (
	"bufio"
	"bytes"
	"context"
	"encoding/binary"
	"errors"
	"io"
	"net"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

// One owned worker, with phase/peer-close observations separate from worker join.
// Neither peer EOF nor the parent's descriptor closure alone proves Rust join.
type bridgeTransportStall struct {
	listener       net.Listener
	mu             sync.Mutex
	closed         bool
	conn           net.Conn
	phase, peerEOF chan bool
	done           chan struct{}
}

func newBridgeTransportStall(t *testing.T, kex bool) *bridgeTransportStall {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal("owned stall listener failed")
	}
	s := &bridgeTransportStall{listener: listener, phase: make(chan bool, 1), peerEOF: make(chan bool, 1), done: make(chan struct{})}
	t.Cleanup(func() {
		s.mu.Lock()
		s.closed = true
		_ = s.listener.Close()
		if s.conn != nil {
			_ = s.conn.Close()
		}
		s.mu.Unlock()
		timer := time.NewTimer(3 * time.Second)
		defer timer.Stop()
		select {
		case <-s.done:
		case <-timer.C:
			t.Error("owned stall worker join deadline exceeded")
		}
	})
	go s.serve(kex)
	return s
}

func (s *bridgeTransportStall) serve(kex bool) {
	defer close(s.done)
	phaseSent := false
	defer func() {
		if !phaseSent {
			s.phase <- false
		}
	}()
	conn, err := s.listener.Accept()
	if err != nil {
		return
	}
	s.mu.Lock()
	if s.closed {
		s.mu.Unlock()
		_ = conn.Close()
		return
	}
	s.conn = conn
	s.mu.Unlock()
	defer func() {
		_ = conn.Close()
		s.mu.Lock()
		s.conn = nil
		s.mu.Unlock()
	}()
	if conn.SetDeadline(time.Now().Add(3*time.Second)) != nil {
		return
	}
	if kex {
		if _, err := io.WriteString(conn, "SSH-2.0-fixture-stall\r\n"); err != nil {
			return
		}
	}
	reader := bufio.NewReaderSize(conn, 256)
	banner, err := reader.ReadSlice('\n') // Bounded even for a missing newline.
	if err != nil || !bytes.HasPrefix(banner, []byte("SSH-2.0-")) || !bytes.HasSuffix(banner, []byte("\r\n")) {
		return
	}
	if kex {
		var length [4]byte
		if _, err := io.ReadFull(reader, length[:]); err != nil {
			return
		}
		n := binary.BigEndian.Uint32(length[:])
		if n < 6 || n > 32768 || (n+4)%8 != 0 {
			return
		}
		packet := make([]byte, int(n))
		if _, err := io.ReadFull(reader, packet); err != nil {
			return
		}
		padding := int(packet[0])
		valid := padding >= 4 && padding < len(packet)-1 && packet[1] == 20
		clear(packet)
		if !valid {
			return
		}
	}
	s.phase <- true
	phaseSent = true
	// No response is sent after phaseReached; require the actual peer to close.
	if conn.SetReadDeadline(time.Now().Add(3*time.Second)) != nil {
		s.peerEOF <- false
		return
	}
	var next [1]byte
	n, err := reader.Read(next[:])
	s.peerEOF <- n == 0 && errors.Is(err, io.EOF)
}

func bridgeTransportObservation(t *testing.T, observation <-chan bool, bound time.Duration) {
	t.Helper()
	timer := time.NewTimer(bound)
	defer timer.Stop()
	select {
	case ok := <-observation:
		if !ok {
			t.Fatal("owned stall observation failed")
		}
	case <-timer.C:
		t.Fatal("owned stall observation deadline exceeded")
	}
}

func TestBridgeTransport(t *testing.T) {
	for _, mode := range []string{"kex-success", "host-mismatch", "id-deadline", "id-cancel", "kex-deadline", "kex-cancel", "pre-cancel"} {
		t.Run(mode, func(t *testing.T) {
			deadline := uint32(3000)
			if strings.HasSuffix(mode, "-deadline") {
				deadline = 500
			}
			fixture, frame := bridgeFixtureFrame(t, deadline)
			defer clear(frame)
			var stall *bridgeTransportStall
			var mismatch *Fixture
			if mode == "host-mismatch" {
				var err error
				mismatch, err = NewFixture()
				if err != nil {
					t.Fatal("owned mismatch fixture failed")
				}
				t.Cleanup(func() {
					if mismatch.Close() != nil {
						t.Error("owned mismatch fixture close failed")
					}
				})
				host := mismatch.HostKey().Marshal()
				offset := 18 + int(frame[13])
				if len(host) != int(binary.BigEndian.Uint16(frame[14:16])) {
					t.Fatal("owned host wire length mismatch")
				}
				copy(frame[offset:offset+len(host)], host)
			}
			if strings.HasPrefix(mode, "id-") || strings.HasPrefix(mode, "kex-") && mode != "kex-success" {
				stall = newBridgeTransportStall(t, strings.HasPrefix(mode, "kex-"))
				_, portText, err := net.SplitHostPort(stall.listener.Addr().String())
				if err != nil {
					t.Fatal("owned stall endpoint invalid")
				}
				port, err := strconv.ParseUint(portText, 10, 16)
				if err != nil {
					t.Fatal("owned stall port invalid")
				}
				binary.BigEndian.PutUint16(frame[6:8], uint16(port))
			}
			child, err := StartBridgeChild(context.Background(), bridgeFixtureBinary, frame)
			if err != nil {
				t.Fatal("owned transport child start failed")
			}
			// Registered last: child cancellation and reap precede either server cleanup.
			t.Cleanup(func() { _ = child.Close() })
			bridgeReady(t, child)
			if mode == "pre-cancel" {
				if child.Control('C') != nil {
					t.Fatal("fixed pre-cancellation failed")
				}
			} else {
				if child.Control('G') != nil {
					t.Fatal("fixed transport start failed")
				}
				if stall != nil {
					bridgeTransportObservation(t, stall.phase, 2*time.Second)
				}
				if strings.HasSuffix(mode, "-cancel") {
					if child.Control('C') != nil {
						t.Fatal("fixed transport cancellation failed")
					}
				}
			}
			result := bridgeWait(t, child)
			failure := mode == "host-mismatch" || strings.HasSuffix(mode, "-deadline")
			if failure {
				if !errors.Is(result.err, ErrBridgeChildIO) || result.summary.ExitCode != 2 || result.summary.Diagnostic != "fixture SSH failure" {
					t.Fatal("fixed SSH failure summary invalid")
				}
			} else if result.err != nil || result.summary.ExitCode != 0 || result.summary.Diagnostic != "" {
				t.Fatal("KEX stage success summary invalid")
			}
			bridgeRemainingEvents(t, child, []string{"not-dispatched", "joined"})
			if result.summary.StdoutBytes > 4096 || result.summary.StderrBytes > 4096 {
				t.Fatal("transport output cap exceeded")
			}
			if _, err := child.conn.Write([]byte{'G'}); !errors.Is(err, net.ErrClosed) {
				t.Fatal("owned parent descriptor not closed")
			}
			if stall != nil {
				bridgeTransportObservation(t, stall.peerEOF, 3*time.Second)
			}
			// Stats exclude authentication and exec; they do not count TCP attempts.
			if fixture.Stats() != (FixtureStats{}) {
				t.Fatal("transport stage attempted authentication or exec")
			}
			if mismatch != nil && mismatch.Stats() != (FixtureStats{}) {
				t.Fatal("mismatch fixture attempted authentication or exec")
			}
		})
	}
}
