package sshlab

import (
	"bytes"
	"context"
	"errors"
	"testing"
)

func TestDialMatchingTrust(t *testing.T) {
	f := rejectionFixture(t)
	trusted := append([]byte(nil), f.HostKey().Marshal()...)
	client, err := Dial(context.Background(), f.Endpoint(), f.HostKey(), f.ClientSigner())
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()
	session, err := client.NewSession()
	if err != nil {
		t.Fatal(err)
	}
	defer session.Close()
	output, err := session.Output("fixture.complete")
	if err != nil || string(output) != "fixture complete\n" {
		t.Fatalf("output %q: %v", output, err)
	}
	stats := f.Stats()
	if stats.AuthCallbacks == 0 || stats.ExecAttempts != 1 || stats.Commands != 1 || !bytes.Equal(trusted, f.HostKey().Marshal()) {
		t.Fatalf("stats/trust: %+v", stats)
	}
}
func TestDialTrustAndCredentials(t *testing.T) {
	for _, mode := range []string{"unknown", "changed", "wrong-signer"} {
		t.Run(mode, func(t *testing.T) {
			f := rejectionFixture(t)
			other := rejectionFixture(t)
			expected, signer := f.HostKey(), f.ClientSigner()
			var wanted error
			switch mode {
			case "unknown":
				expected = nil
				wanted = ErrUnknownHost
			case "changed":
				expected = other.HostKey()
				wanted = ErrChangedHost
			case "wrong-signer":
				signer = other.ClientSigner()
			}
			var before []byte
			if expected != nil {
				before = append([]byte(nil), expected.Marshal()...)
			}
			client, err := Dial(context.Background(), f.Endpoint(), expected, signer)
			if client != nil {
				_ = client.Close()
				t.Fatal("rejected connection returned client")
			}
			if err == nil || wanted != nil && !errors.Is(err, wanted) {
				t.Fatalf("unexpected error: %v", err)
			}
			if err := f.Close(); err != nil {
				t.Fatal(err)
			}
			stats := f.Stats()
			if stats.ExecAttempts != 0 || stats.Commands != 0 || wanted != nil && stats.AuthCallbacks != 0 || wanted == nil && stats.AuthCallbacks == 0 {
				t.Fatalf("stats: %+v", stats)
			}
			if expected != nil && !bytes.Equal(before, expected.Marshal()) {
				t.Fatal("supplied trust changed")
			}
		})
	}
}
func TestDialRejectsInputsBeforeConnection(t *testing.T) {
	f := rejectionFixture(t)
	for _, endpoint := range []string{"invalid", "localhost:22", "192.0.2.1:22", "127.0.0.1:0", "127.0.0.1:65536", "127.0.0.1:+22"} {
		if client, err := Dial(context.Background(), endpoint, f.HostKey(), f.ClientSigner()); err == nil {
			_ = client.Close()
			t.Fatalf("accepted %s", endpoint)
		}
	}
	if client, err := Dial(context.Background(), f.Endpoint(), f.HostKey(), nil); err == nil {
		_ = client.Close()
		t.Fatal("nil signer accepted")
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if client, err := Dial(ctx, f.Endpoint(), f.HostKey(), f.ClientSigner()); !errors.Is(err, context.Canceled) {
		if client != nil {
			_ = client.Close()
		}
		t.Fatalf("cancel error: %v", err)
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}
	if stats := f.Stats(); stats.AuthCallbacks != 0 || stats.ExecAttempts != 0 || stats.Commands != 0 {
		t.Fatalf("input stats: %+v", stats)
	}
}
