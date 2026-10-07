package sshlab

import (
	"bytes"
	"crypto/ed25519"
	"encoding/binary"
	"encoding/pem"
	"errors"

	"golang.org/x/crypto/ssh"
	"regexp"
	"unicode/utf8"
)

var (
	ErrInvalidBridgeFrame = errors.New("invalid bridge frame")
	bridgeID              = regexp.MustCompile(`^[A-Za-z0-9_-]{1,64}$`)
)

type BridgeInput struct {
	Port        uint16
	DeadlineMS  uint32
	Command     byte
	OperationID string
	HostKey     []byte
	PrivateKey  []byte
}

func EncodeBridgeFrame(input BridgeInput) ([]byte, error) {
	bad := func() ([]byte, error) { return nil, ErrInvalidBridgeFrame }
	if input.Port == 0 || input.DeadlineMS == 0 || input.DeadlineMS > 3000 || input.Command > 2 || !bridgeID.MatchString(input.OperationID) || len(input.HostKey) == 0 || len(input.HostKey) > 256 || len(input.PrivateKey) == 0 || len(input.PrivateKey) > 4096 || !utf8.Valid(input.PrivateKey) {
		return bad()
	}
	trimmedPEM := bytes.TrimSpace(input.PrivateKey)
	if !bytes.HasPrefix(trimmedPEM, []byte("-----BEGIN OPENSSH PRIVATE KEY-----\n")) {
		return bad()
	}
	block, rest := pem.Decode(input.PrivateKey)
	if block == nil || block.Type != "OPENSSH PRIVATE KEY" || len(block.Headers) != 0 || len(bytes.TrimSpace(rest)) != 0 {
		return bad()
	}
	pub, err := ssh.ParsePublicKey(input.HostKey)
	if err != nil || pub.Type() != ssh.KeyAlgoED25519 {
		return bad()
	}
	key, err := ssh.ParseRawPrivateKey(input.PrivateKey)
	if err != nil {
		return bad()
	}
	switch key.(type) {
	case ed25519.PrivateKey, *ed25519.PrivateKey:
	default:
		return bad()
	}
	frame := make([]byte, 18+len(input.OperationID)+len(input.HostKey)+len(input.PrivateKey))
	if len(frame) > 8192 {
		return bad()
	}
	copy(frame, "ESLB1\n")
	binary.BigEndian.PutUint16(frame[6:8], input.Port)
	binary.BigEndian.PutUint32(frame[8:12], input.DeadlineMS)
	frame[12], frame[13] = input.Command, byte(len(input.OperationID))
	binary.BigEndian.PutUint16(frame[14:16], uint16(len(input.HostKey)))
	binary.BigEndian.PutUint16(frame[16:18], uint16(len(input.PrivateKey)))
	offset := 18
	copy(frame[offset:], input.OperationID)
	offset += len(input.OperationID)
	copy(frame[offset:], input.HostKey)
	offset += len(input.HostKey)
	copy(frame[offset:], input.PrivateKey)
	return frame, nil
}
