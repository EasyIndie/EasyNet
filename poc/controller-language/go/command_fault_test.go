package sshlab

import (
	"errors"
	"testing"
)

func TestCommandFaultRejectsInvalid(t *testing.T) {
	for _, mode := range []CommandFault{0, 7, 255} {
		fixture, err := NewCommandFaultFixture(mode)
		if fixture != nil || !errors.Is(err, ErrFixtureFault) {
			t.Fatal("invalid fixture mode accepted")
		}
	}
}
