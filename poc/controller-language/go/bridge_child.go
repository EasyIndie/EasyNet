//go:build unix

package sshlab

import (
	"bytes"
	"context"
	"errors"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"syscall"
	"time"
)

var ErrBridgeChildIO = errors.New("bridge child I/O failure")

type BridgeChildSummary struct {
	ExitCode                 int
	StdoutBytes, StderrBytes int
	Diagnostic               string
}
type BridgeChild struct {
	mu                             sync.Mutex
	conn                           net.Conn
	ctx                            context.Context
	cancel                         context.CancelFunc
	goSent, terminal, socketClosed bool
	output                         *bridgeOutput
	done                           chan struct{}
	summary                        BridgeChildSummary
	err                            error
}

// StartBridgeChild accepts only a trusted caller's previously built, owned binary.
// Its containment covers that direct child, not an arbitrary process tree.
func StartBridgeChild(ctx context.Context, binary string, frame []byte) (*BridgeChild, error) {
	if ctx == nil || ctx.Err() != nil || !filepath.IsAbs(binary) || len(frame) > 8192 {
		return nil, ErrBridgeChildIO
	}
	info, err := os.Lstat(binary)
	if err != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0022 != 0 {
		return nil, ErrBridgeChildIO
	}
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok || stat.Uid != uint32(os.Geteuid()) {
		return nil, ErrBridgeChildIO
	}
	childCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	stdout, stderr := newBridgeOutput(true), newBridgeOutput(false)
	var parentFile, childFile *os.File
	var conn net.Conn
	started := false
	defer func() {
		if !started {
			if parentFile != nil {
				parentFile.Close()
			}
			if childFile != nil {
				childFile.Close()
			}
			if conn != nil {
				conn.Close()
			}
			cancel()
			stdout.Finish()
			stderr.Finish()
		}
	}()
	syscall.ForkLock.RLock()
	fds, err := syscall.Socketpair(syscall.AF_UNIX, syscall.SOCK_STREAM, 0)
	if err == nil {
		syscall.CloseOnExec(fds[0])
		syscall.CloseOnExec(fds[1])
	}
	syscall.ForkLock.RUnlock()
	if err != nil {
		return nil, ErrBridgeChildIO
	}
	parentFile, childFile = os.NewFile(uintptr(fds[0]), "bridge-parent"), os.NewFile(uintptr(fds[1]), "bridge-child")
	conn, err = net.FileConn(parentFile) // FileConn duplicates ownership.
	parentFile.Close()
	parentFile = nil
	if err != nil {
		return nil, ErrBridgeChildIO
	}
	cmd := exec.CommandContext(childCtx, binary)
	cmd.Env = []string{"PATH=/usr/bin:/bin", "LANG=C", "LC_ALL=C"}
	cmd.ExtraFiles = []*os.File{childFile} // Dedicated child's sole extra fd is 3.
	cmd.Stdin = bytes.NewReader(append([]byte(nil), frame...))
	cmd.Stdout, cmd.Stderr = stdout, stderr
	cmd.WaitDelay = time.Second
	if cmd.Start() != nil {
		return nil, ErrBridgeChildIO
	}
	childFile.Close()
	childFile = nil
	child := &BridgeChild{conn: conn, ctx: childCtx, cancel: cancel, output: stdout, done: make(chan struct{})}
	started = true
	go func() {
		waitErr := cmd.Wait() // Sole Wait owner; exec's owned pumps finish first.
		child.mu.Lock()
		child.terminal, child.socketClosed = true, true
		conn.Close()
		child.mu.Unlock()
		cancel()
		outErr, diagErr := stdout.Finish(), stderr.Finish()
		out, diag := stdout.Snapshot(), stderr.Snapshot()
		exitCode := -1
		if cmd.ProcessState != nil {
			exitCode = cmd.ProcessState.ExitCode()
		}
		child.summary = BridgeChildSummary{exitCode, out.Bytes, diag.Bytes, diag.Diagnostic}
		switch {
		case errors.Is(outErr, ErrBridgeOutputLimit) || errors.Is(diagErr, ErrBridgeOutputLimit):
			child.err = ErrBridgeOutputLimit
		case errors.Is(outErr, ErrBridgeProtocol) || errors.Is(diagErr, ErrBridgeProtocol):
			child.err = ErrBridgeProtocol
		case waitErr != nil || child.summary.ExitCode != 0:
			child.err = ErrBridgeChildIO
		}
		close(child.done) // Publishes immutable summary/error to all Wait callers.
	}()
	return child, nil
}

func (c *BridgeChild) Events() <-chan string { return c.output.Events() }
func (c *BridgeChild) Control(token byte) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.terminal || (token != 'G' && token != 'C') || (token == 'G' && c.goSent) {
		c.terminal = true
		c.cancel()
		return ErrBridgeProtocol
	}
	if token == 'G' {
		c.goSent = true
	} else {
		c.terminal = true
	}
	deadline, _ := c.ctx.Deadline()
	if c.conn.SetWriteDeadline(deadline) != nil {
		c.terminal = true
		c.cancel()
		return ErrBridgeChildIO
	}
	if n, err := c.conn.Write([]byte{token}); err != nil || n != 1 {
		c.terminal = true
		c.cancel()
		return ErrBridgeChildIO
	}
	return nil
}
func (c *BridgeChild) CloseControl() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.terminal = true
	if c.socketClosed {
		return nil
	}
	c.socketClosed = true
	if c.conn.Close() != nil {
		return ErrBridgeChildIO
	}
	return nil
}
func (c *BridgeChild) Wait() (BridgeChildSummary, error) {
	<-c.done
	return c.summary, c.err
}
func (c *BridgeChild) Close() error {
	c.cancel()
	closeErr := c.CloseControl()
	_, err := c.Wait()
	if err == nil {
		return closeErr
	}
	return err
}
