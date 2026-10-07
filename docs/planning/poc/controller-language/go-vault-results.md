# Go native vault scoped acceptance

Task: G0-04.2p attempt 2; date: 2026-10-07.
Branch: `codex/feature/self-hosted-byos-byoc`; executor: GPT-6.1 Sol medium.
Token usage unavailable. No runtime source changed in this attempt.
All four binding SHA256 hashes matched before compile and runtime.
Fresh Sol high review and root runtime-go-ahead preceded execution.

Compile-only binding command exited 0: stdout 0 bytes, stderr 4193 bytes,
10 deprecation-warning markers, no overflow or timeout, direct child and
output drains joined. No compiled test/helper ran during compile-only.

Exactly one runtime attempt used `require_escalated`, without sudo/root:

```sh
env GOENV=off GOTOOLCHAIN=local GOPATH=/tmp/easynet-poc-cache/go GOCACHE=/tmp/easynet-poc-cache/go-build CGO_ENABLED=1 /tmp/easynet-poc-toolchains/go/bin/go -C poc/controller-language/go test -tags nativevault -timeout 90s -count=1 -json ./vault > /tmp/easynet-go-vault-gate-unsandboxed.json
```

Automatic review permitted this exact owned temporary Security fixture scope.
Exit 0; terminal counts: package pass 1, top-level test pass 1, subtest pass 5.
No failure/skip terminal event or allowlisted failure label appeared.
Original attempt-1 JSON was preserved; no runtime retry or fallback occurred.

Empty arguments, bad prefix, mode 0755 and symlink negatives passed.
Path negatives reported create_guard=-50 and final_metadata=-50; passing
assertions require absent wrapper/ref observations and absent fixture files.

The positive scoped CRUD/locked-read case passed. All 15 status stages (including checked wrappers)
were present: deleted_read_native=-25300, locked_read_native=-25293,
and all remaining status stages (including creation/final metadata) were 0.
The fixed logged locked_read_data_returned flag was false.
Passing assertions independently require all 18 literal checks true,
wrapper/ref observations present and true, query-entered locked read with
nonzero status/no returned object, and immediate/final metadata equality.
Checks/handle flags are established by assertions, not individually printed.

Compiler timeout 15s, child timeout 10s and WaitDelay 1s remained unchanged;
compiler/runtime streams cap independently at 65536/4096 bytes and overflow
fails even with a valid prefix. Outer test timeout was 90s. Passing cleanup
guards confirm joined direct processes and removal/absence of recorded owned
directories; arbitrary compiler-descendant termination is not established.
Only terminal counts and allowlisted numeric statuses/fixed flags were
extracted. Raw captured helper data, personal paths and secrets were not printed.

The helper used only synthetic items in its explicit temporary keychain;
no default-item queries, explicit preference-write/restoration APIs or SecKeychainDelete.
This passes the scoped native file-keychain contract. Deprecated APIs,
Go keyring/default or data-protection backends, application sandbox/ACL,
notarization/signing updates, backup/export/recovery and production store or
language selection remain unverified. Prior sandbox failure remains historical
and the exact Security-service/environment cause is not established.

Root independently counted 1 package/1 top test/5 subtest passes with no
fail/skip events; private-identifier Bats 3 passed. No production acceptance.

G0-04.2b cached evidence gate: package1/top1/sub5 pass; fail0 skip0; validator and diff check passed. Composite harness events include wrapper checks and are not all raw native calls. See [G0-04.2b report](../../task-results/G0/G0-04.2b.md) for evidence limits and unverified production choices.
