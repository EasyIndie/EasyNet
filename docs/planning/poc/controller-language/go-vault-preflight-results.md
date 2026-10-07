# Go vault no-create preflight comparison

Task: G0-04.2s; date: 2026-10-07. Branch: `codex/feature/self-hosted-byos-byoc`.
Reviewed source: `dceb3ca`; all four frozen SHA256 hashes matched before execution.
No runtime code changed. Executor: GPT-6.1 Sol medium; token usage unavailable.

| Environment | Stage | Status | path_guard_ok | Harness result |
| --- | ---: | ---: | --- | --- |
| G0-04.2r actual exec sandbox | 12 | -50 | true | package pass 1 / test pass 1 |
| G0-04.2s exec sandbox override, non-root | 15 | 0 | true | package pass 1 / test pass 1 |

Stage 12 is SecKeychainCopySearchList refusal after CopyDefault and default GetPath
succeeded. Stage 15 marks complete metadata snapshot acquisition. The same reviewed
probe therefore completed its metadata reads in the sandbox-override environment.
This comparison supports an environment-dependent refusal; it does not establish
the underlying Security-service cause or a general platform failure.

Executed exactly once, with `require_escalated` and no sudo/root transition:

```sh
env GOENV=off GOTOOLCHAIN=local GOPATH=/tmp/easynet-poc-cache/go GOCACHE=/tmp/easynet-poc-cache/go-build CGO_ENABLED=1 /tmp/easynet-poc-toolchains/go/bin/go -C poc/controller-language/go test -tags nativeprobe -timeout 45s -count=1 -json ./vault > /tmp/easynet-go-vault-probe-unsandboxed.json
```

Automatic review permitted the precise read-only Security-service/owned temporary
fixture scope. Command exit 0. JSON terminal counts: package pass 1, test pass 1;
no failure/skip terminal events. Only fixed stage/status/path_guard_ok values and
terminal counts were extracted; captured compiler/runtime data and personal paths
were not printed or stored in this report.

The unchanged harness retained compiler timeout 15s/runtime timeout 10s,
WaitDelay 1s, independent output caps 65536/4096 bytes and outer timeout 45s.
No allowlisted timeout, overflow, malformed/unexpected-data, fixture-creation or
cleanup failure appeared. Test pass confirms joined direct-child completion,
fixture absence, recorded owned-directory removal and its absence check.
This is not proof of arbitrary compiler descendant termination on a timeout.

The dedicated `--probe` branch used only metadata getters and released snapshot
references; creation, unlock, item queries/CRUD, lock/delete and preference writes
were unreachable. No nativevault run, mutation, retry, fallback, code edit, state
edit or commit occurred. Native create/unlock/CRUD/lock and installed metadata
invariance remain unverified. G0-04.2p remains blocked pending root disposition.
This harness pass is diagnostic delivery, not native vault acceptance.
