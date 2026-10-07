package sshlab

import (
	"errors"
	"sync"
)

const outputLimit = 4096

var ErrOutputLimit = errors.New("combined output limit exceeded")

type boundedOutput struct {
	mu       sync.Mutex
	data     []byte
	overflow bool
}

func (output *boundedOutput) Write(data []byte) (int, error) {
	output.mu.Lock()
	defer output.mu.Unlock()
	if output.overflow {
		return 0, ErrOutputLimit
	}
	accepted := len(data)
	if remaining := outputLimit - len(output.data); accepted > remaining {
		accepted = remaining
		output.overflow = true
	}
	output.data = append(output.data, data[:accepted]...)
	if output.overflow {
		return accepted, ErrOutputLimit
	}
	return accepted, nil
}
func (output *boundedOutput) Bytes() []byte {
	output.mu.Lock()
	defer output.mu.Unlock()
	return append([]byte(nil), output.data...)
}
func (output *boundedOutput) Overflowed() bool {
	output.mu.Lock()
	defer output.mu.Unlock()
	return output.overflow
}
