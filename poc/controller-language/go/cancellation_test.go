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
)

func TestDialLiveCancellation(t *testing.T) {
	for _, phase := range []string{"handshake", "auth"} {
		t.Run(phase, func(t *testing.T) {
			f, err := NewAuthStallFixture()
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = f.Close() })
			endpoint := f.Endpoint()
			reached := make(chan error, 1)
			if phase == "handshake" {
				listener, err := net.Listen("tcp", "127.0.0.1:0")
				if err != nil {
					t.Fatal(err)
				}
				endpoint = listener.Addr().String()
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
					if _, err := conn.Write([]byte("SSH-2.0-fixture-cancel\r\n")); err != nil {
						reached <- err
						return
					}
					banner, err := bufio.NewReader(conn).ReadString('\n')
					if err == nil && !strings.HasPrefix(banner, "SSH-2.0-") {
						err = fmt.Errorf("invalid client identification %q", banner)
					}
					reached <- err
					<-release
				}()
				t.Cleanup(func() { _ = listener.Close(); close(release); worker.Wait() })
			}
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			returned := make(chan error, 1)
			go func() {
				client, err := Dial(ctx, endpoint, f.HostKey(), f.ClientSigner())
				if client != nil {
					_ = client.Close()
					err = errors.New("stalled dial returned client")
				}
				returned <- err
			}()
			if phase == "handshake" {
				select {
				case err := <-reached:
					if err != nil {
						t.Fatal(err)
					}
				case <-time.After(time.Second):
					t.Fatal("identification phase missing")
				}
			} else {
				select {
				case <-f.AuthReached():
				case <-time.After(time.Second):
					t.Fatal("auth phase missing")
				}
			}
			cancel()
			select {
			case err := <-returned:
				if !errors.Is(err, context.Canceled) {
					t.Fatalf("cancel error: %v", err)
				}
			case <-time.After(time.Second):
				t.Fatal("live cancellation exceeded one second")
			}
			if err := f.Close(); err != nil {
				t.Fatal(err)
			}
			stats := f.Stats()
			if stats.ExecAttempts != 0 || stats.Commands != 0 || phase == "auth" && stats.AuthCallbacks == 0 || phase == "handshake" && stats.AuthCallbacks != 0 {
				t.Fatalf("cancel stats: %+v", stats)
			}
		})
	}
}
func TestRunBlockedCancellationAndDeadline(t *testing.T) {
	for _, mode := range []string{"cancel", "deadline"} {
		t.Run(mode, func(t *testing.T) {
			f := rejectionFixture(t)
			client, err := Dial(context.Background(), f.Endpoint(), f.HostKey(), f.ClientSigner())
			if err != nil {
				t.Fatal(err)
			}
			ctx, cancel := context.WithCancel(context.Background())
			if mode == "deadline" {
				cancel()
				ctx, cancel = context.WithTimeout(context.Background(), 100*time.Millisecond)
			}
			defer cancel()
			type response struct {
				result Result
				err    error
			}
			started := make(chan struct{})
			returned := make(chan response, 1)
			go func() {
				result, err := run(ctx, client, "fixture-cancel-1", "fixture.block", started)
				returned <- response{result, err}
			}()
			select {
			case <-f.BlockReached():
			case <-time.After(time.Second):
				t.Fatal("block dispatch not observed")
			}
			select {
			case <-started:
			case <-time.After(time.Second):
				t.Fatal("client exec acknowledgement missing")
			}
			if mode == "cancel" {
				cancel()
			}
			var reply response
			select {
			case reply = <-returned:
			case <-time.After(time.Second):
				t.Fatal("Run cancellation exceeded one second")
			}
			expected := context.Canceled
			if mode == "deadline" {
				expected = context.DeadlineExceeded
			}
			if !errors.Is(reply.err, expected) || reply.result.Outcome != "unknown" || !reply.result.OwnerRetained || reply.result.OperationID != "fixture-cancel-1" {
				t.Fatalf("unknown binding: %+v %v", reply.result, reply.err)
			}
			if f.PendingBlocks() != 1 {
				t.Fatal("client cancellation cleared independent pending block")
			}
			if stats := f.Stats(); stats.ExecAttempts != 1 || stats.Commands != 1 {
				t.Fatalf("no replay stats: %+v", stats)
			}
			if err := f.Close(); err != nil {
				t.Fatal(err)
			}
			if f.PendingBlocks() != 0 {
				t.Fatal("fixture cleanup did not release pending handler")
			}
		})
	}
}
