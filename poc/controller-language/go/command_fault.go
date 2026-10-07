package sshlab

import "errors"

// CommandFault configures only disposable fixed-command server observations.
type CommandFault uint8

const (
	noCommandFault CommandFault = iota
	ChannelOpenStall
	ExecAckStall
	AckLost
	NoStatus
	NonzeroStatus
	NoClose
)

var ErrFixtureFault = errors.New("invalid fixture fault")

func NewCommandFaultFixture(mode CommandFault) (*Fixture, error) {
	// Reject before key generation/listener creation, including internal zero.
	if mode < ChannelOpenStall || mode > NoClose {
		return nil, ErrFixtureFault
	}
	return newFixture(false, mode)
}
func (f *Fixture) PhaseReached() <-chan struct{} { return f.phaseReached }
func (f *Fixture) reachPhase()                   { f.phaseOnce.Do(func() { close(f.phaseReached) }) }
