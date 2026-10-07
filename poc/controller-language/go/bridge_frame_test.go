package sshlab

import (
	"crypto/ecdsa"
	"crypto/ed25519"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"encoding/binary"
	"encoding/pem"
	"errors"
	"testing"

	"golang.org/x/crypto/ssh"
)

func TestBridgeFrame(t *testing.T) {
	_, private, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	signer, err := ssh.NewSignerFromKey(private)
	if err != nil {
		t.Fatal(err)
	}
	host := signer.PublicKey().Marshal()
	block, err := ssh.MarshalPrivateKey(private, "")
	if err != nil {
		t.Fatal(err)
	}
	privatePEM := pem.EncodeToMemory(block)
	input := BridgeInput{Port: 23456, DeadlineMS: 3000, Command: 2, OperationID: "a_1", HostKey: append([]byte(nil), host...), PrivateKey: append([]byte(nil), privatePEM...)}
	frame, err := EncodeBridgeFrame(input)
	if err != nil {
		t.Fatal(err)
	}
	if string(frame[:6]) != "ESLB1\n" || binary.BigEndian.Uint16(frame[6:8]) != input.Port || binary.BigEndian.Uint32(frame[8:12]) != input.DeadlineMS || frame[12] != 2 || frame[13] != 3 || int(binary.BigEndian.Uint16(frame[14:16])) != len(host) || int(binary.BigEndian.Uint16(frame[16:18])) != len(privatePEM) {
		t.Fatal("header mismatch")
	}
	offset := 18
	if string(frame[offset:offset+3]) != input.OperationID {
		t.Fatal("ID mismatch")
	}
	offset += 3
	if string(frame[offset:offset+len(host)]) != string(host) {
		t.Fatal("host key mismatch")
	}
	offset += len(host)
	if string(frame[offset:]) != string(privatePEM) || len(frame) != 18+3+len(host)+len(privatePEM) {
		t.Fatal("private key or total length mismatch")
	}
	input.HostKey[0] ^= 0xff
	input.PrivateKey[0] ^= 0xff
	if string(frame[offset:]) != string(privatePEM) || string(frame[21:21+len(host)]) != string(host) || string(frame[18:21]) != "a_1" {
		t.Fatal("frame aliases caller memory")
	}
	validID := BridgeInput{Port: 1, DeadlineMS: 1, OperationID: "x", HostKey: host, PrivateKey: privatePEM}
	if _, err := EncodeBridgeFrame(validID); err != nil {
		t.Fatal(err)
	}
	for _, bad := range []BridgeInput{
		{Port: 0, DeadlineMS: 1, Command: 0, OperationID: "x", HostKey: host, PrivateKey: privatePEM},
		{Port: 1, DeadlineMS: 0, Command: 0, OperationID: "x", HostKey: host, PrivateKey: privatePEM},
		{Port: 1, DeadlineMS: 3001, Command: 0, OperationID: "x", HostKey: host, PrivateKey: privatePEM},
		{Port: 1, DeadlineMS: 1, Command: 3, OperationID: "x", HostKey: host, PrivateKey: privatePEM},
		{Port: 1, DeadlineMS: 1, Command: 0, OperationID: string(bytesRepeat('a', 65)), HostKey: host, PrivateKey: privatePEM},
		{Port: 1, DeadlineMS: 1, Command: 0, OperationID: "bad/id", HostKey: host, PrivateKey: privatePEM},
		{Port: 1, DeadlineMS: 1, Command: 0, OperationID: "é", HostKey: host, PrivateKey: privatePEM},
		{Port: 1, DeadlineMS: 1, Command: 0, OperationID: "x", HostKey: nil, PrivateKey: privatePEM},
		{Port: 1, DeadlineMS: 1, Command: 0, OperationID: "x", HostKey: host, PrivateKey: nil},
		{Port: 1, DeadlineMS: 1, Command: 0, OperationID: "x", HostKey: []byte{1}, PrivateKey: privatePEM},
		{Port: 1, DeadlineMS: 1, Command: 0, OperationID: "x", HostKey: bytesRepeat('x', 257), PrivateKey: privatePEM},
		{Port: 1, DeadlineMS: 1, Command: 0, OperationID: "x", HostKey: host, PrivateKey: []byte("PKCS8")},
		{Port: 1, DeadlineMS: 1, Command: 0, OperationID: "x", HostKey: host, PrivateKey: append(append([]byte(nil), privatePEM...), []byte("extra")...)},
		{Port: 1, DeadlineMS: 1, Command: 0, OperationID: "x", HostKey: host, PrivateKey: append([]byte("prefix"), privatePEM...)},
		{Port: 1, DeadlineMS: 1, Command: 0, OperationID: "x", HostKey: host, PrivateKey: append(append([]byte(nil), privatePEM...), bytesRepeat(' ', 4097)...)},
		{Port: 1, DeadlineMS: 1, Command: 0, OperationID: "x", HostKey: host, PrivateKey: append(append([]byte(nil), privatePEM...), 0xff)},
	} {
		if frame, err := EncodeBridgeFrame(bad); !errors.Is(err, ErrInvalidBridgeFrame) || frame != nil {
			t.Fatal("invalid input was accepted or error was not fixed sentinel")
		}
	}
	other, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	otherSigner, err := ssh.NewSignerFromKey(other)
	if err != nil {
		t.Fatal(err)
	}
	if frame, err := EncodeBridgeFrame(BridgeInput{Port: 1, DeadlineMS: 1, OperationID: "x", HostKey: otherSigner.PublicKey().Marshal(), PrivateKey: privatePEM}); !errors.Is(err, ErrInvalidBridgeFrame) || frame != nil {
		t.Fatal("accepted non-Ed25519 host key")
	}
	otherBlock, err := ssh.MarshalPrivateKey(other, "")
	if err != nil {
		t.Fatal("cannot marshal synthetic non-Ed25519 key")
	}
	if frame, err := EncodeBridgeFrame(BridgeInput{Port: 1, DeadlineMS: 1, OperationID: "x", HostKey: host, PrivateKey: pem.EncodeToMemory(otherBlock)}); err != ErrInvalidBridgeFrame || frame != nil {
		t.Fatal("accepted non-Ed25519 OpenSSH private key")
	}
	pkcs8, err := x509.MarshalPKCS8PrivateKey(private)
	if err != nil {
		t.Fatal(err)
	}
	pkcs8PEM := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: pkcs8})
	if frame, err := EncodeBridgeFrame(BridgeInput{Port: 1, DeadlineMS: 1, OperationID: "x", HostKey: host, PrivateKey: pkcs8PEM}); !errors.Is(err, ErrInvalidBridgeFrame) || frame != nil {
		t.Fatal("accepted PKCS8")
	}
	longID := BridgeInput{Port: 1, DeadlineMS: 1, OperationID: string(bytesRepeat('a', 64)), HostKey: host, PrivateKey: privatePEM}
	if _, err := EncodeBridgeFrame(longID); err != nil {
		t.Fatal("64-byte ID rejected")
	}
}
func bytesRepeat(char byte, n int) []byte {
	b := make([]byte, n)
	for i := range b {
		b[i] = char
	}
	return b
}
