# Rust candidate result CLI evidence

G0-04.2f implements ResultLab-v1 in one private `labresult` binary. This is
candidate B evidence; production language selection remains pending.

## Contract and implementation

The six fields are decoded by a custom Serde map visitor using borrowed
`RawValue`. Decoded key equality rejects escaped duplicates; unknown/case-alias
keys and missing fields fail. Exact lexical version `1` and output integer
`0|[1-9][0-9]*` reject fractions, exponents, negative zero and overflow.
Independent validation enforces ASCII IDs, byte bounds and outcome/owner pairs.
Input reads at most 4097 bytes, accepts at most 4096 valid UTF-8 bytes, and
requires the JSON deserializer to reach the end of input.

The private summary borrows typed `ResultRecord`, maps `Outcome`, copies ID and
ownership and retains only output length. It validates even rejected caller IDs.
Encoding validates before writing, serializes six keys in fixed order and uses
one write; partial writes fail without an atomic-delivery claim. Parser and I/O
errors are replaced by fixed errors. The CLI rejects any argument with exit 2,
emits normalized JSON without a newline on success, and reports only fixed
argument/input/I/O messages. No SSH or vault action runs through this CLI.

Exact dependencies: existing serde 1.0.229 plus serde_json 1.0.151 with default
features disabled and `std,raw_value`. Scoped root-package resolution preserved
all existing locked package versions; only itoa 1.0.18, serde_json 1.0.151 and
zmij 1.0.23 were added. An initial cache miss required authorized registry fetch
into the isolated PoC cache; runtime tests and release build use locked offline
commands. No global tool installation occurred.

## Verification

Targeted locked offline tests passed: three inline unit tests and two integration
tests. The CLI integration test exercises 30 actual owned binary subprocesses,
including the Go CLI cases, additional exact-number and UTF-8 failures, accepted
byte boundaries and ownership outcomes. Each subprocess has a three-second
limit, bounded stdin, separate pipe reader threads retaining at most 4096 bytes
while draining excess, and owned child kill/wait cleanup. These direct finite
binary cases do not establish arbitrary subprocess-tree cleanup behavior.
Pure I/O tests inject reader failure, writer failure and a short write; invalid
encoding writes nothing. A capture test checks both exact and exceeded limits.

Final test compilation took 2.25 seconds; unit execution 0.00 seconds and
integration execution 0.58 seconds. Final run had no warnings. The first test
attempt failed to compile a diagnostic byte-array branch; one local repair
converted both branches to slices. This is separate from cache preparation.

Locked offline release build succeeded in 29.80 seconds with one warning:
`rust-objcopy` stripping failed (SIGABRT; missing `@rpath/libLLVM.dylib`).
Sol high approved final source with no blocking findings. Root read-only host
inspection recorded the following actual release artifact facts; all commands
exited zero, with no signing or notarization operation.

| Host artifact observation | Actual result |
|---|---|
| Host / toolchain | macOS 27.0 arm64 / temporary Rust 1.99.0 |
| Temporary release binary | `/tmp/easynet-poc-cache/rust-target/release/labresult` |
| Size / SHA-256 | 577960 bytes / `d6803fb5e87c9eaf03961cbe2981893fdf44e9c8aa5206bfeb958df152905db3` |
| file / otool | Mach-O arm64 / libiconv.2 and libSystem |
| codesign display / verify | adhoc linker-signed0x20002, TeamIdentifier absent / valid on disk, exit0 |

Debug stripping was not qualified due to the retained LLVM warning. These flags
differ from the Go host build, so sizes do not establish a fair language ranking.
No Developer ID, notarization, installer, other-platform or declared-MSRV
qualification follows. Production language decision remains separate ADR-004.
