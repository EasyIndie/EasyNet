package sshlab

import (
	"context"
	"errors"
	"strings"
	"testing"
)

func TestRunObservedAndOverflow(t *testing.T) {
	for _, command := range []string{"fixture.complete", "fixture.large"} {
		t.Run(command, func(t *testing.T) {
			f := rejectionFixture(t)
			client, err := Dial(context.Background(), f.Endpoint(), f.HostKey(), f.ClientSigner())
			if err != nil {
				t.Fatal(err)
			}
			result, err := Run(context.Background(), client, "fixture_operation-1", command)
			if err := f.Close(); err != nil {
				t.Fatal(err)
			}
			if result.OperationID != "fixture_operation-1" || !result.OwnerRetained || len(result.Output) > outputLimit {
				t.Fatalf("result binding: %+v", result)
			}
			if command == "fixture.complete" {
				if err != nil || result.Outcome != "fixture-complete-observed" || string(result.Output) != "fixture complete\n" {
					t.Fatalf("observed result %+v: %v", result, err)
				}
			} else if !errors.Is(err, ErrOutputLimit) || result.Outcome != "unknown" || len(result.Output) != outputLimit {
				t.Fatalf("overflow result %+v: %v", result, err)
			}
			if stats := f.Stats(); stats.ExecAttempts != 1 || stats.Commands != 1 {
				t.Fatalf("no retry stats: %+v", stats)
			}
			if _, err := client.NewSession(); err == nil {
				t.Fatal("owned client remains open")
			}
		})
	}
}
func TestRunRejectsBeforeDispatch(t *testing.T) {
	for _, mode := range []string{"empty-id", "long-id", "unsafe-id", "command", "nil-context", "cancelled"} {
		t.Run(mode, func(t *testing.T) {
			f := rejectionFixture(t)
			client, err := Dial(context.Background(), f.Endpoint(), f.HostKey(), f.ClientSigner())
			if err != nil {
				t.Fatal(err)
			}
			ctx, operationID, command := context.Background(), "fixture-1", "fixture.complete"
			switch mode {
			case "empty-id":
				operationID = ""
			case "long-id":
				operationID = strings.Repeat("a", 65)
			case "unsafe-id":
				operationID = "unsafe/id"
			case "command":
				command = "arbitrary"
			case "nil-context":
				ctx = nil
			case "cancelled":
				var cancel context.CancelFunc
				ctx, cancel = context.WithCancel(ctx)
				cancel()
			}
			result, err := Run(ctx, client, operationID, command)
			if err == nil || result.OperationID != operationID || result.Outcome != "not-dispatched" || result.OwnerRetained || len(result.Output) != 0 {
				t.Fatalf("pre-dispatch %+v: %v", result, err)
			}
			if err := f.Close(); err != nil {
				t.Fatal(err)
			}
			if stats := f.Stats(); stats.ExecAttempts != 0 || stats.Commands != 0 {
				t.Fatalf("pre-dispatch stats: %+v", stats)
			}
			if _, err := client.NewSession(); err == nil {
				t.Fatal("owned client remains open")
			}
		})
	}
	result, err := Run(context.Background(), nil, "fixture-1", "fixture.complete")
	if err == nil || result.Outcome != "not-dispatched" || result.OwnerRetained {
		t.Fatalf("nil client: %+v %v", result, err)
	}
}
