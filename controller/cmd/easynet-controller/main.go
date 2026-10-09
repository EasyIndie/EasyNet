package main

import (
	"io"
	"os"
)

const usage = "easynet-controller --version\n"

func run(args []string, out, errOut io.Writer) int {
	if len(args) == 1 && args[0] == "--version" {
		if _, err := io.WriteString(out, "easynet-controller development\n"); err != nil {
			return 1
		}
		return 0
	}
	_, _ = io.WriteString(errOut, usage)
	return 2
}

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}
