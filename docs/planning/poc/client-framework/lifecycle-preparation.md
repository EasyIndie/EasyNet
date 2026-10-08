# Candidate A lifecycle preparation — accepted preparation v1

G0-06.2ab; checked 2026-10-08; **accepted by root for preparation only; runtime remains unqualified**.
This document authorizes no SDK download, bootstrap, build, process or permission action.
Only planning checks ran. Future commands below are proposals; missing tools and
unreviewed flags/templates prevent ready runtime cards. Full G0-06.2/G0-06 gates remain.

## Exact experimental pins and disposition

Choose **Flutter 3.47.0 / bundled Dart 3.13.0, Darwin arm64** for this isolated experiment.
Framework ref: `4cf24164269a5ebf0c16a028a00727d0e77bbb05`;
archive: `stable/macos/flutter_macos_arm64_3.47.0-stable.zip`;
SHA-256: `bd59c85d032a9d81f31ada8c00858bc4f75eded9615b6584390eb13c6ee5083b`.
The [official manifest](https://storage.googleapis.com/flutter_infra_release/releases/releases_macos.json)
was verified by root; [toolchain evidence](toolchain-evidence.md) records the entry.
Current stable is **3.47.6 / Dart 3.13.5**, ref `5fc346839b5d0eef006ed8404392afb4dfae428d`,
arm64 SHA `a1946d3b6b3de15ce247dc89649df9035ce29e6b4e7ebe91919a25890ea2e79a`.
Tradeoff: 3.47.0 matches inspected bootstrap/settings/cache source; it omits subsequent
patches. This is a temporary experiment pin, not production endorsement. Before any
execution, review the 3.47.0→3.47.6 relevant fix delta; a required fix reopens the pin
and source review instead of silently upgrading. Record archive, framework and Dart identity.
Engine: sing-box CLI **1.14.2**, `sing-box-1.14.2-darwin-arm64.tar.gz`,
SHA `925c5382eca8492b0150f868a6db20b18290a38700e621724b3703fd453e032d`;
its official release entry is recorded in toolchain evidence. No binary was fetched.

ADR proposal: qualify only Flutter UI ownership of a CLI process in proxy mode.
CLI child isolation differs from embedded libbox API/ABI, memory, callbacks, packaging
and provider lifecycle. Embedded libbox remains **pending separate pinned bridge PoC
and ADR review**, not equivalent or accepted-not-applicable by this experiment.
Keep Go services separate; native Xray+Reality/Hy2/SS2022/AWG, existing Bash consumers,
metadata v1 and every agreed G0–G6 target remain. The wireguard directory means AWG.

## Owned files, bootstrap and enforceable isolation

Future allocation: one `mkdtemp` root under `/private/tmp`, prefix `easynet-g0-06-2a-`;
freeze its canonical absolute path, owner, inode and run token in the execution binding.
Reject an existing root, symlink components, wrong ownership, or path outside that parent.
Root/subroots: `0700`; fixture/config/log/manifest files: `0600`; `.env` remains `0600`.
Subroots: `downloads/`, `sdk/`, `engine/`, `pub-cache/`, `config/`, `tmp/`, `app/`,
`build/`, `run/`. SDK and build files never enter product/runtime directories.
No personal settings/profile/credential reads, absence probes, or edits are permitted.

Use a reviewed launcher environment allowlist, preserving HOME/CODEX_HOME values without
redefinition; omit unrelated secrets, proxy variables, SSH agent sockets and Git overrides.
Set `PUB_CACHE=<root>/pub-cache` ([Dart documentation](https://dart.dev/tools/pub/environment-variables));
`XDG_CONFIG_HOME=<root>/config` and SDK locator `FLUTTER_ROOT=<root>/sdk/flutter`.
Do not invent analytics/cache environment switches. Flutter's tagged
[runner](https://raw.githubusercontent.com/flutter/flutter/3.47.0/packages/flutter_tools/lib/src/runner/flutter_command_runner.dart)
supports per-invocation `--suppress-analytics` and `--no-version-check`; persistent
`--disable-analytics` is excluded. Suppression is not proof of zero settings writes.
[Settings source](https://raw.githubusercontent.com/flutter/flutter/3.47.0/packages/flutter_tools/lib/src/base/config.dart)
gives `HOME/.flutter_<name>` precedence over XDG: environment relocation alone is insufficient.
[Cache source](https://raw.githubusercontent.com/flutter/flutter/3.47.0/packages/flutter_tools/lib/src/cache.dart)
uses SDK `bin/cache` for downloads/artifacts/locks; `FLUTTER_STORAGE_BASE_URL` selects a
mirror, not cache relocation. Keep official sources; no mirror override is needed.
[Bootstrap source](https://raw.githubusercontent.com/flutter/flutter/3.47.0/bin/internal/shared.sh)
runs Dart pub upgrade with `--suppress-analytics`, changes SDK lock/snapshot/version and
`packages/flutter_tools` state, and can source `bin/internal/bootstrap.sh` before arguments.
Review entrypoints and every invoked updater/bootstrap script before first execution.
TMPDIR relocation is proposed but requires pinned subprocess-source/manual review;
Xcode/Git/Dart helpers and analytics initialization may touch other paths. No claim of closure.

Root found `/usr/bin/sandbox-exec`; its Apple manual marks it deprecated and documents
`sandbox-exec -f profile-file command [arguments...]`. Availability proves no modern
profile compatibility. Proposed kernel-enforced fixture launcher: default deny, explicit
system/Xcode/SDK code reads, owned-root writes only, deny personal-path reads/metadata and
all network except the frozen numeric loopback fixture endpoints in runtime mode.
No broad home, Library, keychain, credentials, user-config or preference access exceptions.
First freeze/review profile syntax, process inheritance, Mach/GUI services and source paths;
then harmless owned-fixture probes must show allowed access, denied outside-root read/write,
denied non-loopback connection and inherited denial in a child. Use synthetic decoys only.
If settings existence lookup fails or Flutter cannot run, stop; never inspect real files or
weaken this boundary. An isolated macOS VM/account is a later reviewed alternative, not ready.
Network-enabled bootstrap is a separate bounded download phase; offline runtime is mandatory.
Review any bootstrap-network exception and transitive URL/hash inventory before enabling it.

Before extraction: verify exact archive SHA against frozen metadata, enumerate all entries,
bound compressed/uncompressed bytes and entry count, reject absolute/`..`/duplicate paths,
special devices/FIFOs/sockets/hardlinks, and symlinks escaping or chaining outside the root.
SDK/framework symlinks may be necessary: accept only explicitly reviewed internal targets
from an extraction manifest; otherwise fail closed. Extract into a new owned staging tree,
without following symlinks or executing content; compare the resulting tree to the manifest.
Strip setuid/setgid; reject unknown xattrs/ACL restoration. Executable SDK/toolchain and
engine entries are an explicit allowlisted exception to fixture `0600`, owner executable
inside `0700` parents; do not blanket chmod all archive files or recursively unknown paths.
Extraction code/tool, expected permission/symlink map and all downloaded scripts need review.
Cleanup rechecks root owner/inode and deletes only manifest-owned descendants without link
following; mismatch retains artifacts and reports a blocker, never broad recursive cleanup.

## Actual UI-host and lifecycle contract v1

One real foreground macOS arm64 Flutter window exposes Connect/Cancel/Stop/Restart and
visible state/error/run token. The app's lifecycle controller starts exactly one pinned
sing-box CLI child with argument array, no shell, normal non-detached process mode, explicit
working directory/environment, bounded streamed output and awaited `exitCode`.
Separate fixture guardian launches the bundle executable directly in a new process group
(no `open`/LaunchServices), tracks host/child identities and pipe lifetime, and survives
harness failure to terminate the owned group. Source-review group inheritance/no-daemon
behavior before runtime; never pkill by name or signal an unverified PID/group.
Normal host shutdown awaits child exit; guardian handles host hard crash/forced harness exit.
Guardian itself killed or reboot recovery remains a release-design gap, not qualified here.

Harness supplies only owned paths/run token and numeric loopback endpoints via arguments.
Fixture is a local HTTP echo server returning the run nonce. Intended engine config:
one SOCKS5 inbound bound `127.0.0.1`, one direct route restricted to the fixture's IPv4/port,
default reject, no DNS resolution/upstream/subscription/TUN/system proxy/routes/user prefs.
Pin/review actual 1.14.2 schema and route semantics in the next contract card; this prose
is not a runnable config. Bind both listeners to explicit loopback; conflicts fail/retry
within the same deadline; no unbounded port search. Sandbox also restricts destinations.
Readiness requires a complete SOCKS5 greeting + CONNECT to the numeric fixture endpoint,
HTTP request and matching nonce response. Spawn success/log text/open port is insufficient.
State machine: idle → starting → ready → stopping → idle; exit/error → failed;
generation token invalidates stale probe/start completions. Calls serialize per generation.
Proposed bounds: start/probe 5s, individual IO 1s, graceful stop 2s, kill/reap 2s;
overall case 15s, suite 180s; monotonic absolute deadlines include spawn/output/cleanup.
Cap each stdout/stderr stream at 64KiB retained, continue draining with byte counters;
overflow reports/truncates, never blocks exit. Stop closes probes, sends TERM, then KILL
if necessary, awaits exit and closed pipes, removes only owned fixture files.
Repeated Connect while starting/ready must reuse the generation without a second process;
Restart first completes stop/reap, then increments generation. No automatic retry loop.

Frozen cases: genuine readiness+nonce; Stop; child forced crash→failed→explicit Restart;
three Connect/Stop cycles; duplicate/concurrent Connect; Cancel before spawn/during probe;
invalid config; occupied port; silent/hung readiness; output flood; absolute timeout;
window close; forced host crash; harness failure/cancel and guardian pipe EOF cleanup.
Every case records UI state transitions, owned PIDs/generation, proxy probe, exit status,
deadline/output counters and cleanup. Assert no owned child/group or listener survives;
verify both ports reusable and manifest files gone. A leak fails the suite and stops reuse.
Controller-only/headless tests support implementation, but cannot qualify the UI-host gate.

## Immediate isolation-probe contract v1 — proposed, not runtime-ready

Code root `P=poc/client-framework`; document root `D=docs/planning/poc/client-framework`.
One I card writes only `P/lab/isolate.py`, `P/lab/fixture.sb`, `P/lab/test_isolate.py`; proposed command `python3 -I P/lab/test_isolate.py`.
Order: root accepts contract → implement without executing → R source/case review → separate frozen fixture-run binding.
No SDK, GUI, Mach-service exceptions or network allow rules belong to this first card.
Allocate fresh `0700 /private/tmp/easynet-g0-06-isolate-<random>` with `allowed/` and sibling `decoy/`, seeded distinct nonce files `seed`, plus manifest-owned `allowed/new`.
Neither directory aliases personal state; record canonical path/owner/inode, reject links.
API: `run_probe(profile_path, allowed_root, argv, deadline_s=2)` returns case, returncode, timed_out, bounded stdout/stderr bytes/counts and reaped; no caller-supplied shell text.
Frozen commands only `/bin/sh`, `/bin/cat`, `/usr/bin/touch`, `/usr/bin/curl` as absolute argv.
Use `/bin/sh -c '/bin/cat "$1"' probe <decoy/seed>` only for inherited-child denial.
Minimal env keeps HOME/CODEX_HOME unchanged when present, PATH=/usr/bin:/bin, LC_ALL=C; omit ENV/BASH_ENV, proxies, curlrc/Python/Git overrides and credentials; no rc reads.
Invoke sandbox-exec with argv `-f <reviewed-profile> -D ALLOWED_ROOT=<canonical-allowed> <argv>`.
ALLOWED_ROOT must match `/private/tmp/easynet-g0-06-isolate-[A-Za-z0-9_-]+/allowed`; never interpolate paths into SBPL/shell. Profile path is fixed, owned regular file, hash frozen.
Literal skeleton below is **proposed**: grammar, loader/data paths and modern efficacy need R review.
Root observed version/default-deny, param/subpath and fork/exec grammar in local Apple profiles; private interfaces may change. Do not import system.sb/CoreFoundation or user-access rules.
```scheme
(version 1)
(deny default)
(allow file-read* (literal "/bin/sh") (literal "/bin/cat")
  (literal "/usr/bin/touch") (literal "/usr/bin/curl")
  (subpath "/usr/lib") (subpath "/System/Library/dyld"))
(allow file-read* file-write* (subpath (param "ALLOWED_ROOT")))
(allow process-fork)
(allow process-exec (literal "/bin/sh") (literal "/bin/cat")
  (literal "/usr/bin/touch") (literal "/usr/bin/curl"))
```
Freeze cases: allowed cat seed returns nonce; allowed touch new succeeds; decoy cat fails/no nonce; decoy touch new fails with unchanged bytes/names; shell child cat also fails/no nonce.
Harness starts a real owned numeric `127.0.0.1` listener, first proves it reachable outside the sandbox; sandbox curl `-q --noproxy '*' --max-time 1 http://127.0.0.1:<port>/` fails and listener sees no connection. No external address.
Each command gets 2s including TERM/KILL/reap, output cap 8KiB/stream with continued drain; suite deadline 20s. Signal only exact owned PIDs/group; timeout/leak/ambiguous denial fails.
Close/join listener, inspect synthetic manifest paths only; retain root on failure. Success unlinks known seed/new files, then rmdir allowed/decoy/root; unexpected entries stop cleanup.
Passing proves only these fixture cases. Later SDK/GUI/Mach/loopback exceptions require new review.

Subsequent bounded cards remain proposed: extraction/bootstrap source review → staging (`P/lab/stage.py`, test/manifest; proposed `python3 -I P/lab/stage.py --root <root> --verify-only`) → template generation/review → exact loopback config/fixture → controller (`lib/lifecycle.dart`) → visible host (`lib/main.dart`) → unsigned-build review → guardian/harness → real UI qualification.
Each card stays ≤3 implementation + ≤2 test/document writes. Proposed commands after flag/source review:
`<sdk>/bin/flutter --suppress-analytics --no-version-check create --platforms=macos --no-pub --org com.example <root>/app/easynet_lifecycle`;
then `test --no-pub <frozen-test>` and `build macos --debug --no-pub` with the same global flags,
and `python3 -I P/lab/harness.py --app <bundle-executable> --engine <engine> --root <run-root> --case all`.
Exact controller/widget/guardian test paths, template scope and unsigned mechanism need separate bindings.

Generated templates exceed the handwritten budget: write only the declared temporary tree;
review the full path/hash/type manifest, locks, plugin registrant, entitlements/build/signing.
Do not count generated Xcode/Swift/config as two Dart files: any import needs bounded batches
or a reviewed generated-artifact exception; otherwise copy reviewed Dart changes to the owned root.
No-plugin CocoaPods requirement and unsigned GUI launch are unknown.
Root reports Flutter/Dart/sing-box absent, Xcode27/xcrun present, pod absent in PATH; no packages, SDKs, signing identities or user state were inspected/executed here.

Real NE/provider, TUN, user consent, entitlement, signing, distribution, minimum OS/arch,
licenses and real four-protocol client acceptance remain pending; a proxy-only unsigned UI
experiment cannot discharge them. Ask only for concrete later targets/permissions after review.
