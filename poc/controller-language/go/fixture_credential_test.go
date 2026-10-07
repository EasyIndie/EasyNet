package sshlab

import (
	"bytes"
	"crypto/rand"
	"errors"
	"sync"
	"testing"

	"golang.org/x/crypto/ssh"
)

func credentialFixture(t *testing.T) *Fixture {
	t.Helper()
	f, err := NewFixture()
	if err != nil {
		t.Fatal("owned fixture setup failed")
	}
	t.Cleanup(func() {
		if f.Close() != nil {
			t.Error("owned fixture close failed")
		}
	})
	return f
}
func matchingCredential(t *testing.T, f *Fixture, encoded []byte) {
	t.Helper()
	signer, err := ssh.ParsePrivateKey(encoded)
	if err != nil {
		t.Fatal("fixture credential parsing failed")
	}
	if !bytes.Equal(signer.PublicKey().Marshal(), f.ClientSigner().PublicKey().Marshal()) {
		t.Fatal("fixture credential public key mismatch")
	}
}
func TestFixtureCredentialMatchingIndependentCopiesAndClose(t *testing.T) {
	f := credentialFixture(t)
	first, err := f.ClientPrivateKeyPEM()
	if err != nil {
		t.Fatal("fixture credential export failed")
	}
	matchingCredential(t, f, first)
	clear(first)
	second, err := f.ClientPrivateKeyPEM()
	if err != nil {
		t.Fatal("independent credential export failed")
	}
	matchingCredential(t, f, second)
	defer clear(second)
	f.mu.Lock()
	stored := f.clientPrivate
	f.mu.Unlock()
	if f.Close() != nil {
		t.Fatal("fixture close failed")
	}
	for _, b := range stored {
		if b != 0 {
			t.Fatal("stored credential copy not cleared")
		}
	}
	if encoded, err := f.ClientPrivateKeyPEM(); encoded != nil || !errors.Is(err, ErrFixtureCredential) {
		t.Fatal("closed fixture credential accepted")
	}
	// Original signer remains usable: Close cleared only its separate stored copy.
	signature, err := f.ClientSigner().Sign(rand.Reader, []byte("fixture challenge"))
	if err != nil || f.ClientSigner().PublicKey().Verify([]byte("fixture challenge"), signature) != nil {
		t.Fatal("legacy signer changed by close")
	}
}
func TestFixtureCredentialConcurrentSnapshotsAndClose(t *testing.T) {
	f := credentialFixture(t)
	var group sync.WaitGroup
	start := make(chan struct{})
	group.Add(9)
	for i := 0; i < 8; i++ {
		go func() {
			defer group.Done()
			<-start
			encoded, err := f.ClientPrivateKeyPEM()
			if err != nil {
				if encoded != nil || !errors.Is(err, ErrFixtureCredential) {
					t.Error("credential refusal not fixed")
				}
				return
			}
			defer clear(encoded)
			signer, parseErr := ssh.ParsePrivateKey(encoded)
			if parseErr != nil || !bytes.Equal(signer.PublicKey().Marshal(), f.ClientSigner().PublicKey().Marshal()) {
				t.Error("concurrent credential mismatch")
			}
		}()
	}
	go func() {
		defer group.Done()
		<-start
		if f.Close() != nil {
			t.Error("concurrent close failed")
		}
	}()
	close(start)
	group.Wait()
	if encoded, err := f.ClientPrivateKeyPEM(); encoded != nil || !errors.Is(err, ErrFixtureCredential) {
		t.Fatal("post-close credential accepted")
	}
}
func TestFixtureCredentialInvalidReceivers(t *testing.T) {
	for _, f := range []*Fixture{nil, {}, {clientPrivate: []byte{1}}} {
		encoded, err := f.ClientPrivateKeyPEM()
		if encoded != nil || !errors.Is(err, ErrFixtureCredential) {
			t.Fatal("invalid credential accepted")
		}
		if err.Error() != "invalid fixture credential" {
			t.Fatal("credential error not fixed")
		}
	}
}
