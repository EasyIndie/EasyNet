package sshlab

import (
	"golang.org/x/crypto/ssh"
	"net"
	"testing"
	"time"
)

func TestFixtureComplete(t *testing.T) {
	f, err := NewFixture()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = f.Close() })
	conn, err := net.DialTimeout("tcp", f.Endpoint(), 3*time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	if err := conn.SetDeadline(time.Now().Add(3 * time.Second)); err != nil {
		t.Fatal(err)
	}
	transport, channels, requests, err := ssh.NewClientConn(conn, f.Endpoint(), &ssh.ClientConfig{
		User: "fixture", Auth: []ssh.AuthMethod{ssh.PublicKeys(f.ClientSigner())},
		HostKeyCallback: ssh.FixedHostKey(f.HostKey()), Timeout: 3 * time.Second,
	})
	if err != nil {
		t.Fatal(err)
	}
	client := ssh.NewClient(transport, channels, requests)
	defer client.Close()
	session, err := client.NewSession()
	if err != nil {
		t.Fatal(err)
	}
	defer session.Close()
	output, err := session.Output("fixture.complete")
	if err != nil || string(output) != "fixture complete\n" {
		t.Fatalf("complete output %q, error %v", output, err)
	}
	stats := f.Stats()
	if stats.AuthCallbacks == 0 || stats.ExecAttempts != 1 || stats.Commands != 1 {
		t.Fatalf("stats: %+v", stats)
	}
	if f.Close() != nil || f.Close() != nil {
		t.Fatal("Close failed")
	}
}
