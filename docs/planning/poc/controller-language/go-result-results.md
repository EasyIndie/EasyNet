# Go candidate result CLI / host artifact facts

G0-04.2c implements `cmd/labresult` against result-lab-v1. It accepts no
arguments, reads one bounded stdin record through `DecodeLabRecord`, and emits
the canonical six-field JSON through `EncodeLabRecord`, with no added newline.
Success exits 0; rejected input, I/O failures and arguments exit 2 with fixed
stderr lines `invalid lab input`, `lab I/O failure`, and
`invalid lab arguments`, respectively. Input and raw exception details are never
echoed. Failed output writes may be partial. `main` delegates to `run` so reader,
writer and short-write failures can be injected without opening external targets.

On 2026-10-07, the frozen command passed (package elapsed 1.529s):

```sh
env GOENV=off GOTOOLCHAIN=local GOPATH=/tmp/easynet-poc-cache/go GOCACHE=/tmp/easynet-poc-cache/go-build /tmp/easynet-poc-toolchains/go/bin/go -C poc/controller-language/go test -timeout 90s -count=1 -json ./cmd/labresult
```

Actual binary fixtures cover canonical roundtrip, whitespace normalization,
4096-byte input, empty/malformed input, duplicate and escaped-equivalent keys,
null, 4097-byte input, second JSON value and extra arguments. Rejections assert
empty stdout, exact fixed stderr and exit 2. Injected reader, writer and short
writes assert the fixed I/O error. The named capped writer has no embedded
buffer; a separate boundary check verifies acceptance of 4096 bytes and rejection
of the next byte. Test builds use an owned temporary directory, 15s compile
deadline, 3s child deadlines, 1s `WaitDelay` and independently capped 4096-byte
stdout/stderr writers. These are bounds for these owned fixtures, not arbitrary
process-tree cleanup guarantees or stdin timeouts in the CLI itself.

Read-only host artifact observation used a separate temporary build of the same
implementation with default build flags; build deadline 15s, inspection commands
5s each. Repository base: `35c66ed5aaa790076ff0fe022506f5dadc17aca7`, with
the uncommitted CLI source. Artifact remains temporary, outside the repository:
`/private/var/folders/z0/1h35x82j7d767_fm_x3tvdsh0000gn/T/easynet-g0-04-2c-ts4v7yeq/labresult`.

| Observation | Actual result |
|---|---|
| Host | macOS 27.0, arm64 |
| Toolchain | `go version go1.27.1 darwin/arm64` |
| Build environment | GOOS=darwin, GOARCH=arm64, CGO_ENABLED=1 |
| Size | 5,680,018 bytes |
| SHA-256 | `b85ec65faa6e2f033b08817066dbd659b6c4ca43fec0ba34a8b4cad6931f5753` |
| `file` (exit 0) | Mach-O 64-bit executable arm64 |
| `otool -L` (exit 0) | libSystem.B.dylib, libresolv.9.dylib, CoreFoundation and Security frameworks |
| `codesign -dv --verbose=4` (exit 0) | flags `0x20002(adhoc,linker-signed)`; `Signature=adhoc`; `TeamIdentifier=not set`; identifier `a.out` |

No signing or notarization command was run. These host observations establish
neither Developer ID identity nor platform support, installer/update delivery,
release readiness or a production language decision. This CLI performs no SSH,
vault, native-helper, network or deployment operation. Importing the existing
lab package retains its host build/link dependencies, as observed above.
