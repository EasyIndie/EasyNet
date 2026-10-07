# Rust B SSH transport / bridge proposal v1

G0-04.2v; 2026-10-07; root security-reviewed design. This supplements
[SSH lab v1](ssh-lab-contract.md), without changing its A/B assertions or choosing
a production language. No Rust SSH behavior has passed. Current pins/features
remain those in `poc/controller-language/rust/Cargo.toml`; no vendor/runtime fork.
Go owns the existing synthetic fixture and Rust owns one client child. This is
a macOS/Unix PoC interface, not Windows or minimum-OS qualification.

## Credentials and local IPC

Proposed child: `poc/controller-language/rust/src/bin/ssh_fixture.rs`, no arguments.
Go launches only the owned, previously built binary; no shell or imported path.
stdin carries one binary credential frame then EOF; fd 3 carries control bytes
over a Go-owned Unix socketpair. Here “control pipe” means owned local IPC,
not an `os.Pipe` or another loopback listener. Root accepted this design variation.
No Tokio `io-std`/`fs` feature, blocking control-reader thread or extra dependency.
Go passes exactly the child socket via `ExtraFiles`, closes its local copy after
Start, and retains the parent socket until cleanup. Rust checks fd 3 is a stream
Unix socket, transfers ownership once with a narrowly documented `FromRawFd`,
sets nonblocking and registers it as `tokio::net::UnixStream`; no other inherited fd.
Control reading is a retained async future, never a detached task.

Credential frame: magic six bytes `ESLB1\n`; then big-endian fields port u16,
deadline-ms u32, command u8, operation-ID length u8, host-key length u16,
private-key length u16; then ID, expected host key and private key bytes.
Total frame <=8192 bytes; no trailing bytes; truncated/extra data rejects.
Port is nonzero and supplied only from the parent's owned fixture endpoint;
Rust constructs literal IPv4 `127.0.0.1`, never resolves names or accepts hosts.
Deadline is 1..3000 ms; ID is 1..64 ASCII `[A-Za-z0-9_-]`; username is `fixture`.
Commands 0/1/2 map only to `fixture.complete`/`fixture.block`/`fixture.large`.
Host bytes are the SSH wire public-key blob, 1..256 bytes; an absent key is a
separate typed untrusted test input, rejected before dial (not an empty wire blob).
Private key is UTF-8 unencrypted OpenSSH PEM, 1..4096 bytes, Ed25519 only.
Go uses `ClientSigner().(ssh.CryptoSigner).CryptoSigner()` and
`ssh.MarshalPrivateKey(..., "")`, then `pem.EncodeToMemory`; no key file.
Rust uses memory-only `russh::keys::decode_secret_key(text, None)`; never
`load_secret_key`, known-hosts/agent APIs, HOME, personal vault or subprocess SSH.
Parser support is an interface proposal, not a passed Go-to-Rust key decode test.
Wrong-key cases substitute an independently generated ephemeral client key;
host mismatch substitutes independently generated expected bytes. Expected trust
is supplied by the parent and never learned from the connection under test.
Buffers and decoded keys live only through the owned test; no guaranteed
zeroization claim for library allocations, kernel pipes, allocator or compiler.

Parent writes the complete credential frame and closes stdin before any GO.
Child reads at most 8193 bytes through EOF before constructing its runtime;
parent bounds that phase by the child deadline and reaps on refusal/hang.
Control tokens are single bytes: `G` permits the one dispatch; `C` cancels.
EOF, unknown/duplicate tokens or any read error cancel/refuse; never replay.
No GO is sent until the parent has observed child `ready`. Pre-cancel sends C
without G; post-ack cancel waits for child `ack` and independent BlockReached.
The child emits only these fixed ASCII lines on stdout, in phase order:
`ready`, `authenticated`, `ack`, and one terminal line `not-dispatched`,
`unknown`, or `fixture-complete-observed`, followed by `joined` on proved cleanup.
`ready` means validated input/control setup, not SSH establishment. No IDs,
keys, endpoints or command output appear on the event pipe. Each line <=64 bytes;
parent caps total stdout and stderr independently at 4096 bytes, without an
embedded buffer/ReaderFrom bypass. SSH stdout+stderr has a separate combined
4096-byte cap. Output is counted in memory; never emitted as diagnostic data.
Fixed stderr categories only: `invalid fixture input`, `fixture I/O failure`,
`fixture SSH failure`, `fixture cleanup failure`; never format raw exceptions.
Exit 0 requires a successful fixture operation and joined cleanup; refusals/failures exit 2. The parent asserts the expected exit/event sequence for each scenario.
Bridge events are lab rendezvous, not JSON result records or production receipts.

## Trust, dispatch, cancellation and joining

Unknown trust refuses before dial. Handler compares exact Ed25519 public-key
wire bytes against the independent expected bytes; false/error never authenticates.
Use signed public-key auth only; no password, PTY, subsystem, agent or forwarding.
One session/one exec with `want_reply=true`; `exec().await` only queues a message
(`channels/mod.rs:235–240`). Only the corresponding `ChannelMsg::Success`
is dispatch acknowledgement (`client/encrypted.rs:794–803`). Allow no other
reply-requesting channel operation, so Success cannot acknowledge another request.
Data/status/EOF/close are bounded observations; completion requires fixed expected
output, successful exit-status and channel close, preserving operation ownership.

Dial with retained Tokio connect future under the absolute deadline. After dial,
convert the owned socket to std, retain one `try_clone()` exclusively for
`Shutdown::Both`, then register the original as Tokio again. Wrap that original
in `OwnedStream` with a one-shot Drop notification. No duplicated read/write user.
Pin and retain `connect_stream(...)`; select by borrowing `&mut future` so cancel
or deadline does not drop it. On interruption, shut down the owned clone and
continue polling the same future. Early SSH-ID failures happen before spawn;
after spawn, KEX failure takes `join.await` before returning its error
(`client/mod.rs:1219–1226`). This corrects the preparation note's implied KEX-error
join loss. A retained future returning Err on that path does join the session.
Successful KEX returns Handle; a cancellation/KEX-success race must still take
that Handle through cleanup. Handle's Future awaits its join (`1124–1136`);
Handle Drop only logs (`316–320`). Dropping pending connect/Handle is prohibited.
Drop channel receivers before joining, so blocked channel event delivery can
resolve; callbacks may not await bridge writes or arbitrary user work.
Shutdown, await retained connect result/returned Handle, and observe OwnedStream
drop within a separate 1000 ms cleanup allowance. Stream drop alone does not
prove task join; shutdown alone does not prove task termination. Emit `joined`
only after the relevant future/Handle has resolved and stream drop was observed.
If cleanup exceeds allowance, emit fixed cleanup failure if possible; parent
kills and reaps only its direct child and fails the test. Process containment
is not internal join evidence. No arbitrary process-tree cleanup claim.
Source permits this design but does not prove bounded runtime cleanup: that
remains a mandatory fault-test gate. A failing gate requires a separate reviewed
dependency/API disposition; never silently vendor, change runtime or remove B.

| Observation / injected point | Required result and independent evidence |
|---|---|
| Untrusted/mismatch/wrong key | No exec; mismatch auth callbacks 0; joined cleanup |
| Deadline at SSH-ID/KEX/auth | No exec; fixed failure; joined cleanup within allowance |
| C before G | not-dispatched, owner false, no exec; joined cleanup |
| Exec queued, ack lost | unknown, owner true, same ID; no replay |
| Ack + BlockReached, then C | unknown, owner true, same ID; PendingBlocks remains 1 |
| Combined output overflow | <=4096 retained; unknown after dispatch; joined cleanup |
| Complete observed | fixture-complete-observed, owner true; joined cleanup |

Parent observes fixture Stats, AuthReached/BlockReached and PendingBlocks, using
bounded rendezvous rather than sleeps. PendingBlocks is checked before Close;
client shutdown must not claim to cancel that fixture-owned pending operation.
Finally parent closes only its own fixture, waits Close, then checks pending 0.
Parent drains capped event/error streams, closes IPC, waits direct-child exit;
child runtime terminates only after owned futures/tasks join. No claim about
remote cancellation, terminal reconciliation or durable ownership is introduced.

## Proposed small cards (root must prepare/review bindings)

Each authored code/test change <=200 lines; separate test cards if needed.
1. Frame codec: Go `bridge_frame.go` / `bridge_frame_test.go`; Rust
   `src/bridge_frame.rs` / `tests/bridge_frame.rs`; `EncodeBridgeFrame(BridgeInput) ([]byte,error)` and `decode_frame(&[u8])->Result<Credentials,LabError>`.
   Freeze shared byte vectors, limits, malformed cases, memory key decode and redaction.
2. Owned IPC runner: Go `bridge_child.go` / `bridge_child_test.go`; Rust
   `src/bin/ssh_fixture.rs`; `StartChild(ctx,binary,frame) (*Child,error)`,
   `Child.Control(byte) error`, `Child.Wait() error`; fixed events, fd ownership,
   EOF/invalid controls, capped streams and direct-child timeout/reaping only.
3. Transport ownership: Rust `src/transport.rs` / `tests/transport.rs` plus the
   narrow `src/lib.rs` export; `connect_owned(Credentials,Cancel)->JoinedConnection`,
   `JoinedConnection.close_join(deadline)->Result<(),LabError>`; first prove
   SSH-ID/KEX/host-refusal timeout/cancel races and Drop-versus-join observations.
4. Auth/dispatch: Rust `src/ssh_run.rs` plus separate bridge tests; typed
   `RunInput`, `RunResult`, `run(input,cancel,events)->Result<RunResult,LabError>`;
   signed auth, wrong key, fixed commands and actual Success rendezvous.
5. Fault matrix: separate cards for auth stall, combined output cap, before-G /
   ack-lost / post-ack cancellation, pending-state and cleanup; same A/B assertions.
Vault, strict JSON/CLI packaging and final candidate B acceptance remain separate
agreed scope. These proposed paths/interfaces unlock no runtime task by themselves.
