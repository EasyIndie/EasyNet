# Rust B SSH preparation — source observations

2026-10-07; preparation only, not a passed Rust experiment or language decision.
Source inspected from the checksum-verified russh 0.64.1 crate used by the
[shared SSH contract](ssh-lab-contract.md). No Rust client/server was run.

- The crate declares MSRV 1.89; temporary compiler 1.99.0 is available.
  Candidate dependency remains russh =0.64.1, default features disabled, ring.
  Its published Cargo.lock pins Tokio 1.52.3, serde 1.0.228 and serde_json 1.0.150.
  These are reproducible starting pins, not a newly resolved or audited closure.
- Its client example accepts every server key. That example policy must not be
  copied: unknown trust refuses before dial; changed trust refuses before auth.
- channels/mod.rs exec queues an Exec message; return success proves local send,
  not acknowledgement. client/encrypted.rs CHANNEL_SUCCESS forwards a
  ChannelMsg::Success. Observe that event before testing post-ack cancellation.
- client/mod.rs Handle::Drop only logs; it is not a joined cleanup guarantee.
  Handle implements Future over its session JoinHandle. connect_stream spawns
  the session and waits for KEX before returning Handle; on KEX signal failure it
  explicitly awaits the join (client/mod.rs:1219–1226). Dropping the pending
  connect future can still lose the join path. Timeout alone cannot certify cleanup.
- The B adapter must retain the owned connect/session future, close its owned
  transport on cancellation/overflow, and join the future/handle. The exact
  transport interruption design remains to be frozen and proved by fault tests.
  An external process timeout is containment, not proof of internal task cleanup.
- Reuse Go's closed synthetic loopback fixture and the same signed auth, valid
  refusal requests, phase-observed timeout/cancel, combined cap, actual ack,
  retained unknown ownership/no replay, independent pending-state and cleanup
  matrix. Ephemeral credentials travel through owned pipes, never CLI arguments,
  personal files or logs. A fixture bridge remains unimplemented.

Primary artifact: [russh 0.64.1 crate](https://crates.io/crates/russh/0.64.1),
SHA256 `ba61e87b9ec9a39a59a6bbed4c0b8ff7fb07073405b24a767a1f2c8560ac8f58`.
Inspected source selectors: Cargo.toml; Cargo.lock Tokio/serde/serde_json entries;
examples/client_exec_simple.rs Handler; src/client/mod.rs Handle/Drop/Future and
connect_stream; src/channels/mod.rs exec; src/client/encrypted.rs CHANNEL_SUCCESS.
Registry checksum verifies the artifact, not its security or runtime behavior.
B cards remain locked until exact files, interfaces and commands are reviewed.
