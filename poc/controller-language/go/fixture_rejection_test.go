package sshlab

import (
	"bufio"
	"crypto/ed25519"
	"crypto/rand"
	"errors"
	"net"
	"strings"
	"sync"
	"testing"
	"time"

	"golang.org/x/crypto/ssh"
)

func rejectionFixture(t *testing.T) *Fixture {
	t.Helper()
	f, err := NewFixture()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = f.Close() })
	return f
}
func fixtureClient(t *testing.T, f *Fixture, signer ssh.Signer) (*ssh.Client, error) {
	t.Helper()
	conn, err := net.DialTimeout("tcp", f.Endpoint(), 3*time.Second)
	if err != nil {
		return nil, err
	}
	if err := conn.SetDeadline(time.Now().Add(3 * time.Second)); err != nil {
		_ = conn.Close()
		return nil, err
	}
	transport, channels, requests, err := ssh.NewClientConn(conn, f.Endpoint(), &ssh.ClientConfig{
		User: "fixture", Auth: []ssh.AuthMethod{ssh.PublicKeys(signer)}, HostKeyCallback: ssh.FixedHostKey(f.HostKey()),
	})
	if err != nil {
		_ = conn.Close()
		return nil, err
	}
	client := ssh.NewClient(transport, channels, requests)
	t.Cleanup(func() { _ = client.Close() })
	return client, nil
}
func TestFixtureWrongKey(t *testing.T) {
	f := rejectionFixture(t)
	_, private, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	wrong, err := ssh.NewSignerFromKey(private)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := fixtureClient(t, f, wrong); err == nil {
		t.Fatal("wrong key accepted")
	}
	if stats := f.Stats(); stats.AuthCallbacks == 0 || stats.ExecAttempts != 0 || stats.Commands != 0 {
		t.Fatalf("stats: %+v", stats)
	}
}
func TestFixtureRequestRejections(t *testing.T) {
	f := rejectionFixture(t)
	client, err := fixtureClient(t, f, f.ClientSigner())
	if err != nil {
		t.Fatal(err)
	}
	endpoint, err := net.ResolveTCPAddr("tcp", f.Endpoint())
	if err != nil {
		t.Fatal(err)
	}
	forward := ssh.Marshal(struct {
		DestAddr   string
		DestPort   uint32
		OriginAddr string
		OriginPort uint32
	}{endpoint.IP.String(), uint32(endpoint.Port), "127.0.0.1", uint32(endpoint.Port)})
	channel, _, err := client.OpenChannel("direct-tcpip", forward)
	if err == nil {
		_ = channel.Close()
		t.Fatal("forward channel accepted")
	}
	var denied *ssh.OpenChannelError
	if !errors.As(err, &denied) || denied.Reason != ssh.Prohibited {
		t.Fatalf("forward channel error: %v", err)
	}
	allocation := ssh.Marshal(struct {
		Address string
		Port    uint32
	}{"127.0.0.1", 0})
	accepted, _, err := client.SendRequest("tcpip-forward", true, allocation)
	if err != nil || accepted {
		t.Fatalf("global forwarding: accepted=%v error=%v", accepted, err)
	}
	channel, _, err = client.OpenChannel("session", nil)
	if err != nil {
		t.Fatal(err)
	}
	defer channel.Close()
	requests := []struct {
		kind    string
		payload []byte
	}{
		{"pty-req", ssh.Marshal(struct {
			Term                         string
			Columns, Rows, Width, Height uint32
			Modes                        string
		}{"xterm", 1, 1, 0, 0, "\x00"})},
		{"subsystem", ssh.Marshal(struct{ Name string }{"sftp"})},
		{"exec", []byte{0xff}},
		{"exec", ssh.Marshal(struct{ Command string }{"arbitrary command"})},
	}
	for _, request := range requests {
		accepted, err := channel.SendRequest(request.kind, true, request.payload)
		if err != nil || accepted {
			t.Fatalf("%s: accepted=%v error=%v", request.kind, accepted, err)
		}
	}
	if stats := f.Stats(); stats.ExecAttempts != 2 || stats.Commands != 0 {
		t.Fatalf("stats: %+v", stats)
	}
}
func joinedClose(t *testing.T, f *Fixture) {
	t.Helper()
	done := make(chan struct{})
	errors := make(chan error, 2)
	go func() {
		var workers sync.WaitGroup
		for range 2 {
			workers.Add(1)
			go func() { defer workers.Done(); errors <- f.Close() }()
		}
		workers.Wait()
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(3 * time.Second):
		t.Fatal("Close did not join")
	}
	for range 2 {
		if err := <-errors; err != nil {
			t.Fatal(err)
		}
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}
	if conn, err := net.DialTimeout("tcp", f.Endpoint(), time.Second); err == nil {
		_ = conn.Close()
		t.Fatal("listener remains open")
	}
}
func TestFixtureCloseStalledHandshake(t *testing.T) {
	f := rejectionFixture(t)
	conn, err := net.DialTimeout("tcp", f.Endpoint(), 3*time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	if err := conn.SetDeadline(time.Now().Add(3 * time.Second)); err != nil {
		t.Fatal(err)
	}
	banner, err := bufio.NewReader(conn).ReadString('\n')
	if err != nil || !strings.HasPrefix(banner, "SSH-2.0-") {
		t.Fatalf("banner %q: %v", banner, err)
	}
	joinedClose(t, f)
	if stats := f.Stats(); stats.AuthCallbacks != 0 || stats.ExecAttempts != 0 || stats.Commands != 0 {
		t.Fatalf("stats: %+v", stats)
	}
}
func TestFixtureCloseBlockedCommand(t *testing.T) {
	f := rejectionFixture(t)
	client, err := fixtureClient(t, f, f.ClientSigner())
	if err != nil {
		t.Fatal(err)
	}
	session, err := client.NewSession()
	if err != nil {
		t.Fatal(err)
	}
	defer session.Close()
	if err := session.Start("fixture.block"); err != nil {
		t.Fatal(err)
	}
	if stats := f.Stats(); stats.ExecAttempts != 1 || stats.Commands != 1 {
		t.Fatalf("acknowledged stats: %+v", stats)
	}
	joinedClose(t, f)
}
