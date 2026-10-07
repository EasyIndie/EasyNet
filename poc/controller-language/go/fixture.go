package sshlab

import (
	"bytes"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/pem"
	"errors"
	"fmt"
	"net"
	"sync"

	"golang.org/x/crypto/ssh"
)

type FixtureStats struct{ AuthCallbacks, ExecAttempts, Commands int }

var ErrFixtureCredential = errors.New("invalid fixture credential")

type Fixture struct {
	blockReached  chan struct{}
	blockOnce     sync.Once
	pendingBlocks int
	authReached   chan struct{}
	authOnce      sync.Once
	listener      net.Listener
	host, client  ssh.Signer
	clientPrivate ed25519.PrivateKey
	config        *ssh.ServerConfig
	mu            sync.Mutex
	stats         FixtureStats
	connections   map[net.Conn]bool
	done          chan struct{}
	once          sync.Once
	workers       sync.WaitGroup
}

func NewFixture() (*Fixture, error)              { return newFixture(false) }
func NewAuthStallFixture() (*Fixture, error)     { return newFixture(true) }
func (f *Fixture) BlockReached() <-chan struct{} { return f.blockReached }
func (f *Fixture) PendingBlocks() int            { f.mu.Lock(); defer f.mu.Unlock(); return f.pendingBlocks }
func (f *Fixture) AuthReached() <-chan struct{}  { return f.authReached }
func newFixture(stallAuth bool) (*Fixture, error) {
	key := func() (ssh.Signer, ed25519.PrivateKey, error) {
		_, private, err := ed25519.GenerateKey(rand.Reader)
		if err != nil {
			return nil, nil, err
		}
		signer, err := ssh.NewSignerFromKey(private)
		return signer, private, err
	}
	host, _, err := key()
	if err != nil {
		return nil, err
	}
	client, private, err := key()
	if err != nil {
		return nil, err
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return nil, err
	}
	f := &Fixture{blockReached: make(chan struct{}), listener: listener, host: host, client: client, connections: make(map[net.Conn]bool), done: make(chan struct{})}
	// Separate storage: closing the fixture must not mutate the legacy signer.
	f.clientPrivate = append(ed25519.PrivateKey(nil), private...)
	if stallAuth {
		f.authReached = make(chan struct{})
	}
	f.config = &ssh.ServerConfig{PublicKeyCallback: func(meta ssh.ConnMetadata, public ssh.PublicKey) (*ssh.Permissions, error) {
		f.mu.Lock()
		f.stats.AuthCallbacks++
		f.mu.Unlock()
		if f.authReached != nil {
			f.authOnce.Do(func() { close(f.authReached) })
			<-f.done
			return nil, fmt.Errorf("fixture authentication stopped")
		}
		if meta.User() != "fixture" || !bytes.Equal(public.Marshal(), client.PublicKey().Marshal()) {
			return nil, fmt.Errorf("fixture authentication rejected")
		}
		return nil, nil
	}}
	f.config.AddHostKey(host)
	f.workers.Add(1)
	go f.accept()
	return f, nil
}
func (f *Fixture) Endpoint() string         { return f.listener.Addr().String() }
func (f *Fixture) HostKey() ssh.PublicKey   { return f.host.PublicKey() }
func (f *Fixture) ClientSigner() ssh.Signer { return f.client }

// ClientPrivateKeyPEM returns a fresh, matching in-memory credential snapshot.
// A snapshot begun before Close may finish afterward; this is not revocation.
func (f *Fixture) ClientPrivateKeyPEM() ([]byte, error) {
	if f == nil {
		return nil, ErrFixtureCredential
	}
	f.mu.Lock()
	select {
	case <-f.done:
		f.mu.Unlock()
		return nil, ErrFixtureCredential
	default:
	}
	if len(f.clientPrivate) != ed25519.PrivateKeySize {
		f.mu.Unlock()
		return nil, ErrFixtureCredential
	}
	private := append(ed25519.PrivateKey(nil), f.clientPrivate...)
	f.mu.Unlock()
	defer clear(private)
	block, err := ssh.MarshalPrivateKey(private, "")
	if err != nil {
		return nil, ErrFixtureCredential
	}
	encoded := pem.EncodeToMemory(block)
	if encoded == nil {
		return nil, ErrFixtureCredential
	}
	return encoded, nil
}
func (f *Fixture) Stats() FixtureStats { f.mu.Lock(); defer f.mu.Unlock(); return f.stats }
func (f *Fixture) Close() error {
	f.once.Do(func() {
		close(f.done)
		_ = f.listener.Close()
		f.mu.Lock()
		clear(f.clientPrivate)
		f.clientPrivate = nil
		for conn := range f.connections {
			_ = conn.Close()
		}
		f.mu.Unlock()
	})
	f.workers.Wait()
	return nil
}
func (f *Fixture) accept() {
	defer f.workers.Done()
	for {
		conn, err := f.listener.Accept()
		if err != nil {
			return
		}
		f.mu.Lock()
		select {
		case <-f.done:
			f.mu.Unlock()
			_ = conn.Close()
			return
		default:
		}
		f.connections[conn] = true
		f.workers.Add(1)
		f.mu.Unlock()
		go f.serve(conn)
	}
}
func (f *Fixture) serve(conn net.Conn) {
	defer f.workers.Done()
	defer func() { _ = conn.Close(); f.mu.Lock(); delete(f.connections, conn); f.mu.Unlock() }()
	server, channels, requests, err := ssh.NewServerConn(conn, f.config)
	if err != nil {
		return
	}
	defer server.Close()
	f.workers.Add(1)
	go func() { defer f.workers.Done(); ssh.DiscardRequests(requests) }()
	for next := range channels {
		if next.ChannelType() != "session" {
			_ = next.Reject(ssh.Prohibited, "fixture session only")
			continue
		}
		channel, reqs, err := next.Accept()
		if err != nil {
			continue
		}
		f.workers.Add(1)
		go func() { defer f.workers.Done(); f.session(channel, reqs) }()
	}
}
func (f *Fixture) session(channel ssh.Channel, requests <-chan *ssh.Request) {
	defer channel.Close()
	for request := range requests {
		var payload struct{ Command string }
		valid := false
		if request.Type == "exec" {
			f.mu.Lock()
			f.stats.ExecAttempts++
			f.mu.Unlock()
			if ssh.Unmarshal(request.Payload, &payload) == nil {
				valid = payload.Command == "fixture.complete" || payload.Command == "fixture.block" || payload.Command == "fixture.large"
			}
		}
		if !valid {
			_ = request.Reply(false, nil)
			continue
		}
		f.mu.Lock()
		f.stats.Commands++
		f.mu.Unlock()
		_ = request.Reply(true, nil)
		switch payload.Command {
		case "fixture.complete":
			_, _ = channel.Write([]byte("fixture complete\n"))
		case "fixture.large":
			var streams sync.WaitGroup
			streams.Add(1)
			go func() { defer streams.Done(); _, _ = channel.Stderr().Write(bytes.Repeat([]byte("e"), 4096)) }()
			_, _ = channel.Write(bytes.Repeat([]byte("o"), 4096))
			streams.Wait()
		case "fixture.block":
			f.mu.Lock()
			f.pendingBlocks++
			f.mu.Unlock()
			f.blockOnce.Do(func() { close(f.blockReached) })
			<-f.done
			f.mu.Lock()
			f.pendingBlocks--
			f.mu.Unlock()
			return
		}
		_, _ = channel.SendRequest("exit-status", false, ssh.Marshal(struct{ Status uint32 }{0}))
		return
	}
}
