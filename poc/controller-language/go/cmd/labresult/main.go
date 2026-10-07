package main

import (
	"errors"
	"fmt"
	"io"
	"os"

	sshlab "easynet.local/ssh-lab"
)

func main() { os.Exit(run(os.Args[1:], os.Stdin, os.Stdout, os.Stderr)) }

func run(args []string, input io.Reader, output, diagnostic io.Writer) int {
	fail := func(message string) int {
		_, _ = fmt.Fprintln(diagnostic, message)
		return 2
	}
	if len(args) != 0 {
		return fail("invalid lab arguments")
	}
	record, err := sshlab.DecodeLabRecord(input)
	if err != nil {
		if errors.Is(err, sshlab.ErrLabRecordIO) {
			return fail("lab I/O failure")
		}
		return fail("invalid lab input")
	}
	if sshlab.EncodeLabRecord(output, record) != nil {
		return fail("lab I/O failure")
	}
	return 0
}
