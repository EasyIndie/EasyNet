GO ?= go
GOFMT ?= gofmt

export GOENV=off
export GOTOOLCHAIN=local
export GOWORK=off
export GOPROXY=off
export GOSUMDB=off
export CGO_ENABLED=0

.PHONY: check fmt-check test

check: fmt-check test

fmt-check:
	@files="$$( $(GOFMT) -l cmd/easynet-controller/*.go )" || exit $$?; test -z "$$files"

test:
	$(GO) test ./...
