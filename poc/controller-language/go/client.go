package sshlab

import (
	"bytes"
	"context"
	"errors"
	"net"
	"strconv"
	"time"

	"golang.org/x/crypto/ssh"
)

var ErrUnknownHost = errors.New("unknown host key")
var ErrChangedHost = errors.New("changed host key")

func Dial(ctx context.Context, endpoint string, expected ssh.PublicKey, signer ssh.Signer) (*ssh.Client, error) {
	if ctx == nil {
		return nil, errors.New("missing context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	host, port, err := net.SplitHostPort(endpoint)
	if err != nil {
		return nil, errors.New("invalid fixture endpoint")
	}
	ip := net.ParseIP(host)
	number, err := strconv.Atoi(port)
	if ip == nil || !ip.IsLoopback() || err != nil || number < 1 || number > 65535 {
		return nil, errors.New("invalid fixture endpoint")
	}
	for _, digit := range port {
		if digit < '0' || digit > '9' {
			return nil, errors.New("invalid fixture port")
		}
	}
	if expected == nil {
		return nil, ErrUnknownHost
	}
	if signer == nil {
		return nil, errors.New("missing signer")
	}
	trusted := append([]byte(nil), expected.Marshal()...)
	deadline := time.Now().Add(3 * time.Second)
	if limit, ok := ctx.Deadline(); ok && limit.Before(deadline) {
		deadline = limit
	}
	dialer := net.Dialer{Deadline: deadline}
	conn, err := dialer.DialContext(ctx, "tcp", endpoint)
	if err != nil {
		return nil, err
	}
	if err := conn.SetDeadline(deadline); err != nil {
		_ = conn.Close()
		return nil, err
	}
	transport, channels, requests, err := ssh.NewClientConn(conn, endpoint, &ssh.ClientConfig{
		User: "fixture", Auth: []ssh.AuthMethod{ssh.PublicKeys(signer)},
		HostKeyCallback: func(_ string, _ net.Addr, observed ssh.PublicKey) error {
			if !bytes.Equal(trusted, observed.Marshal()) {
				return ErrChangedHost
			}
			return nil
		},
	})
	if err != nil {
		_ = conn.Close()
		return nil, err
	}
	return ssh.NewClient(transport, channels, requests), nil
}
