# Rust scoped vault acceptance harness

G0-04.2e prepares candidate B acceptance under NativeVaultLab-v1 and the reviewed
Rust scoped helper-v1 (AR commit `5350fc9`). The harness is **compiled, not native
verified**. Final Sol high source review and the root-controlled single native
attempt remain pending. This evidence does not select a production language or vault.

The Darwin-only `rustvault` Go test uses the existing `sshlab` package and the
prebuilt pinned helper. Before every launch it checks the helper and both private
parent directories with Lstat: effective-user ownership, nonsymlink type, no group
or other write access, regular executable helper, and a bounded SHA256 read matching
the frozen binding. It rejects root, never rebuilds the helper, and uses a 10-second
CommandContext deadline, one-second WaitDelay, separate 4096-byte capped writers,
and empty stderr. Run reaps the child and joins output writers before owned cleanup.

Strict JSON accepts exactly three outer fields, 21 required boolean checks and only
15 optional int32 status names. It rejects unknown, duplicate, missing, null,
trailing and incorrectly typed data; outcomes are pass, blocked or rejected.
Empty arguments require rejected/all false/no statuses. The bad-prefix, 0755 and
owned-symlink cases require blocked, only password_generated true, no wrapper or
keychain reference, exactly create_guard=-50 and final_metadata=-50, and no fixture
file. Positive acceptance requires all 18 native checks, wrapper/reference true,
locked-read data false and all 15 statuses: zero except deleted-read=-25300 and
nonzero locked-read. Logs contain only fixed check summaries and allowlisted
stage names with integer statuses, never raw output, errors, secrets or paths.

All fixtures are newly created direct owned /tmp directories, initially 0700.
The reviewed bad-prefix exception uses `easynet-vault-invalid-*`; all other owned
directories use `easynet-vault-lab-*`. The 0755/symlink mutations apply only to
owned negative fixtures; symlink targets are separately owned and cleaned.
Cleanup removes only exact recorded MkdirTemp paths after helper termination.

The final bound `go test -tags rustvault -c` exited 0 with no warnings; measured
wall/user/system duration was 1.18/0.70/0.44 seconds. No test binary, helper,
--probe, Security API or native case was executed in implementation. The source
contains one gate test with five subtests (four rejection cases and one positive
case); executed native/test counts are zero. Final review and actual native
execution must establish CRUD, metadata invariance, locked-read and cleanup facts.
Deprecated file-Keychain success would still not establish data-protection,
sandbox/ACL, signing, backup/export or recovery support. SSH belongs D and result
JSON belongs F; this card covers scoped vault E only.

## Actual scoped gate

Final Sol high review approved the pinned 280-line harness without blocking findings.
One approved sandbox-override attempt as the non-root host user passed all five
subtests and the parent (package 1.335s; gate 0.50s; no failures or skips).
Four refusal cases created no file. Actual owned native CRUD, deletion/re-add,
lock and queried rejection passed all 18 required checks and 15 status criteria.
The exact locked-read OSStatus was -25293 with no returned data; deleted-read
was -25300, other statuses zero. Immediate/final metadata comparisons and owned
directory cleanup-after-reap checks passed. Runtime evidence is the bounded
JSON stream `/tmp/easynet-rust-vault-gate.json`. Prior compile-only statements
describe implementation; this section records subsequent real native acceptance.
No personal items or preference writes, production vault decision or additional
platform qualification is implied.
