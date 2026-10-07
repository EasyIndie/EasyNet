package sshlab

import (
	"bytes"
	"crypto/ed25519"
	"crypto/rand"
	"fmt"
	"net"
	"sync"

	"golang.org/x/crypto/ssh"
)

type FixtureStats struct{ AuthCallbacks, ExecAttempts, Commands int }
type Fixture struct {
	listener     net.Listener
	host, client ssh.Signer
	config       *ssh.ServerConfig
	mu           sync.Mutex
	stats        FixtureStats
	connections  map[net.Conn]bool
	done         chan struct{}
	once         sync.Once
	workers      sync.WaitGroup
}

func NewFixture() (*Fixture, error) {
	key := func() (ssh.Signer, error) {
		_, private, err := ed25519.GenerateKey(rand.Reader)
		if err != nil {
			return nil, err
		}
		return ssh.NewSignerFromKey(private)
	}
	host, err := key()
	if err != nil {
		return nil, err
	}
	client, err := key()
	if err != nil {
		return nil, err
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return nil, err
	}
	f := &Fixture{listener: listener, host: host, client: client, connections: make(map[net.Conn]bool), done: make(chan struct{})}
	f.config = &ssh.ServerConfig{PublicKeyCallback: func(meta ssh.ConnMetadata, public ssh.PublicKey) (*ssh.Permissions, error) {
		f.mu.Lock()
		f.stats.AuthCallbacks++
		f.mu.Unlock()
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
func (f *Fixture) Stats() FixtureStats      { f.mu.Lock(); defer f.mu.Unlock(); return f.stats }
func (f *Fixture) Close() error {
	f.once.Do(func() {
		close(f.done)
		_ = f.listener.Close()
		f.mu.Lock()
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
			_, _ = channel.Write(bytes.Repeat([]byte("x"), 8192))
		case "fixture.block":
			<-f.done
			return
		}
		_, _ = channel.SendRequest("exit-status", false, ssh.Marshal(struct{ Status uint32 }{0}))
		return
	}
}
