package sshlab

import (
	"errors"
	"sync"
)

var ErrBridgeOutputLimit = errors.New("bridge output limit")
var ErrBridgeProtocol = errors.New("invalid bridge protocol")

type bridgeOutputSnapshot struct {
	Bytes      int
	Diagnostic string
	Failed     bool
}
type bridgeOutput struct {
	mu         sync.Mutex
	events     chan string
	bytes      int
	partial    []byte
	diagnostic string
	err        error
	closed     bool
}

func newBridgeOutput(eventStream bool) *bridgeOutput {
	w := &bridgeOutput{}
	if eventStream {
		w.events = make(chan string, 8)
	}
	return w
}
func (w *bridgeOutput) Events() <-chan string { return w.events }
func (w *bridgeOutput) fail(err error) error {
	if w.err == nil {
		w.err = err
	}
	w.partial = nil
	return w.err
}
func (w *bridgeOutput) Write(p []byte) (int, error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.err != nil {
		return 0, w.err
	}
	if w.closed {
		return 0, w.fail(ErrBridgeProtocol)
	}
	if len(p) > 4096-w.bytes {
		return 0, w.fail(ErrBridgeOutputLimit)
	}
	for i, b := range p {
		if len(w.partial) == 64 {
			return i, w.fail(ErrBridgeOutputLimit)
		}
		w.partial = append(w.partial, b)
		w.bytes++
		if b != '\n' {
			continue
		}
		line := string(w.partial[:len(w.partial)-1])
		w.partial = nil
		if w.events != nil {
			switch line {
			case "ready", "authenticated", "ack", "not-dispatched", "unknown", "fixture-complete-observed", "joined":
				select {
				case w.events <- line:
				default:
					return i + 1, w.fail(ErrBridgeProtocol)
				}
			default:
				return i + 1, w.fail(ErrBridgeProtocol)
			}
		} else {
			if w.diagnostic != "" {
				return i + 1, w.fail(ErrBridgeProtocol)
			}
			switch line {
			case "invalid fixture input", "fixture I/O failure", "fixture SSH failure", "fixture cleanup failure":
				w.diagnostic = line
			default:
				return i + 1, w.fail(ErrBridgeProtocol)
			}
		}
	}
	return len(p), nil
}
func (w *bridgeOutput) Snapshot() bridgeOutputSnapshot {
	w.mu.Lock()
	defer w.mu.Unlock()
	return bridgeOutputSnapshot{w.bytes, w.diagnostic, w.err != nil}
}
func (w *bridgeOutput) Finish() error {
	w.mu.Lock()
	defer w.mu.Unlock()
	if !w.closed {
		w.closed = true
		if len(w.partial) != 0 {
			w.fail(ErrBridgeProtocol)
		}
		if w.events != nil {
			close(w.events)
		}
	}
	return w.err
}
