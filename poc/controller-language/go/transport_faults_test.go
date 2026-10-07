package sshlab

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"net"
	"strings"
	"sync"
	"testing"
	"time"

	"golang.org/x/crypto/ssh"
)

func assertTransportTimeout(t *testing.T, client *ssh.Client, err error, start time.Time) {
	t.Helper()
	if client != nil {
		_ = client.Close()
		t.Fatal("stalled transport returned client")
	}
	var timeout net.Error
	if err == nil || !errors.Is(err, context.DeadlineExceeded) && (!errors.As(err, &timeout) || !timeout.Timeout()) {
		t.Fatalf("expected timeout: %v", err)
	}
	if elapsed := time.Since(start); elapsed >= time.Second {
		t.Fatalf("timeout took %v", elapsed)
	}
}
func TestDialHandshakeDeadline(t *testing.T) {
	f := rejectionFixture(t)
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	reached := make(chan error, 1)
	release := make(chan struct{})
	var worker sync.WaitGroup
	worker.Add(1)
	go func() {
		defer worker.Done()
		conn, err := listener.Accept()
		if err != nil {
			reached <- err
			return
		}
		defer conn.Close()
		if err := conn.SetDeadline(time.Now().Add(3 * time.Second)); err != nil {
			reached <- err
			return
		}
		if _, err := conn.Write([]byte("SSH-2.0-fixture-stall\r\n")); err != nil {
			reached <- err
			return
		}
		banner, err := bufio.NewReader(conn).ReadString('\n')
		if err == nil && !strings.HasPrefix(banner, "SSH-2.0-") {
			err = fmt.Errorf("invalid client SSH identification: %q", banner)
		}
		reached <- err
		<-release
	}()
	var once sync.Once
	cleanup := func() { once.Do(func() { _ = listener.Close(); close(release); worker.Wait() }) }
	t.Cleanup(cleanup)
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	start := time.Now()
	client, err := Dial(ctx, listener.Addr().String(), f.HostKey(), f.ClientSigner())
	assertTransportTimeout(t, client, err, start)
	select {
	case err := <-reached:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("client SSH identification not observed")
	}
	cleanup()
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}
	if stats := f.Stats(); stats.AuthCallbacks != 0 || stats.ExecAttempts != 0 || stats.Commands != 0 {
		t.Fatalf("handshake stats: %+v", stats)
	}
}
func TestDialAuthenticationDeadline(t *testing.T) {
	f, err := NewAuthStallFixture()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = f.Close() })
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	start := time.Now()
	client, err := Dial(ctx, f.Endpoint(), f.HostKey(), f.ClientSigner())
	assertTransportTimeout(t, client, err, start)
	select {
	case <-f.AuthReached():
	case <-time.After(time.Second):
		t.Fatal("auth negotiation not reached")
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}
	if stats := f.Stats(); stats.AuthCallbacks == 0 || stats.ExecAttempts != 0 || stats.Commands != 0 {
		t.Fatalf("auth stats: %+v", stats)
	}
}
