package sshlab

import (
	"context"
	"errors"

	"golang.org/x/crypto/ssh"
)

type Result struct {
	OperationID   string
	Outcome       string
	OwnerRetained bool
	Output        []byte
}
type closingOutput struct {
	*boundedOutput
	client *ssh.Client
}

func (output *closingOutput) Write(data []byte) (int, error) {
	n, err := output.boundedOutput.Write(data)
	if errors.Is(err, ErrOutputLimit) {
		_ = output.client.Close()
	}
	return n, err
}
func Run(ctx context.Context, client *ssh.Client, operationID, command string) (Result, error) {
	result := Result{OperationID: operationID, Outcome: "not-dispatched"}
	if client == nil {
		return result, errors.New("missing owned client")
	}
	defer func() { _ = client.Close(); _ = client.Wait() }()
	if ctx == nil {
		return result, errors.New("missing context")
	}
	if err := ctx.Err(); err != nil {
		return result, err
	}
	if operationID == "" || len(operationID) > 64 {
		return result, errors.New("invalid operation identifier")
	}
	for _, char := range operationID {
		if char != '-' && char != '_' && !(char >= 'a' && char <= 'z') && !(char >= 'A' && char <= 'Z') && !(char >= '0' && char <= '9') {
			return result, errors.New("invalid operation identifier")
		}
	}
	if command != "fixture.complete" && command != "fixture.block" && command != "fixture.large" {
		return result, errors.New("invalid fixture command")
	}
	cancelled := make(chan struct{})
	stop := context.AfterFunc(ctx, func() { _ = client.Close(); close(cancelled) })
	defer func() {
		if !stop() {
			<-cancelled
		}
	}()
	session, err := client.NewSession()
	if err != nil {
		return result, err
	}
	defer session.Close()
	output := &closingOutput{boundedOutput: new(boundedOutput), client: client}
	session.Stdout, session.Stderr = output, output
	if err := ctx.Err(); err != nil {
		return result, err
	}
	result.Outcome, result.OwnerRetained = "unknown", true
	if err := session.Start(command); err != nil {
		return result, err
	}
	err = session.Wait()
	result.Output = output.Bytes()
	if output.Overflowed() {
		return result, ErrOutputLimit
	}
	if cancelled := ctx.Err(); cancelled != nil {
		return result, cancelled
	}
	if err != nil {
		return result, err
	}
	result.Outcome = "fixture-complete-observed"
	return result, nil
}
