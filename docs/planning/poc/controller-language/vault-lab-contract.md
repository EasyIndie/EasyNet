# Native vault language PoC preparation v1

Sol high reviewed official sources for a temporary macOS keychain experiment.
This is a Go/Rust native interoperability comparison, not a production store decision.
The Go keyring package's implicit default/search-list backend cannot be confined to
this fixture; evaluate native Security.framework instead and record that limitation.
Do not test the default personal keychain or claim the wrapper library was accepted.

## Bounded native helper

Use a dedicated helper process with a task-owned temporary directory outside HOME,
an ephemeral password and synthetic secret. SecKeychainCreate must use a private
temporary path, promptUser=false and an explicit returned SecKeychainRef.
Reject root. Only use an euid-owned mode-0700 non-symlink direct
`/tmp/easynet-vault-lab-*` directory resolving below `/private/tmp`, with fixed
nonexisting `fixture.keychain` basename. Reject other paths before Security APIs.
Never use a name containing `/login.keychain`. Disable user interaction in this
helper with SecKeychainSetUserInteractionAllowed(false); bound the process externally.
Set no-UI query behavior too. No real keys, credentials or user-item access.

After an unchanged creation snapshot, explicitly call SecKeychainUnlock only on
ownedRef with the same ephemeral in-memory password (usePassword=true), and require
unlocked status before CRUD. Noninteractive creation is not assumed unlocked.
Add only to `kSecUseKeychain=ownedRef`; constrain every get/update/delete to
`kSecMatchSearchList=[ownedRef]`. Use fixed synthetic service/account namespaces.
Verify create/add/read/update/delete with only fixture values; compare in memory,
never print secret/password/path values. Release all native buffers/references.
Lock only ownedRef, confirm locked status, then attempt a no-UI read: require an
error and no returned secret, recording exact OSStatus, not an invented ErrLocked.
Require an explicit query-entered observation: guard/allocation failure before
SecItemCopyMatching cannot count as a passed locked-read case.
Do not simulate success if the OS refuses the experiment, prompts, or times out.

Snapshot default/search-list metadata read-only before creation, immediately after
creation before any CRUD, and after the experiment;
compare status and path sets/order in memory, emit only equality booleans/statuses.
No preference restoration/writes. Published Apple source excludes private temporary
paths from search-list additions, but installed behavior must be measured.
If a metadata change is detected, fail the experiment and report the actual change;
do not automatically reset user preferences or proceed to further native mutations.

Avoid SecKeychainDelete, whose upstream removal path saves preferences. Release
references and exit the helper first; then remove only its owned temporary directory.
Report cleanup failure instead of deleting guessed paths or following user symlinks.

## Evidence and limits

Go uses CGo with Security/CoreFoundation for the scoped helper. Rust later runs an
equivalent native API experiment with the same outcomes; pin its binding/library.
Deprecated file-keychain behavior does not certify data-protection keychain,
application sandbox/ACL identity, signing updates, backup/export or future recovery.
No language or production credential store is selected here. Safety/source review
and exact runnable file/command binding precede ready; native mutation stays locked
until those facts are frozen. Split helper and native acceptance into small cards.

Primary references reviewed on 2026-10-07:

- [Apple SecKeychainCreate](https://developer.apple.com/documentation/security/seckeychaincreate%28_%3A_%3A_%3A_%3A_%3A_%3A%29).
- [Apple private-path search-list implementation](https://github.com/apple-oss-distributions/Security/blob/main/OSX/libsecurity_keychain/lib/StorageManager.cpp#L108).
- [Add keychain selector](https://developer.apple.com/documentation/security/ksecusekeychain), [query search-list selector](https://developer.apple.com/documentation/security/ksecmatchsearchlist).
- [Process interaction flag](https://github.com/apple-oss-distributions/Security/blob/main/OSX/libsecurity_keychain/lib/SecKeychain.cpp#L809), [removal preference writes](https://github.com/apple-oss-distributions/Security/blob/main/OSX/libsecurity_keychain/lib/StorageManager.cpp#L927).
- [Go keyring v0.2.8 backend](https://github.com/zalando/go-keyring/blob/v0.2.8/keyring_darwin.go).

## Failed sandbox preflight follow-up

G0-04.2p ran once: four rejection cases passed, positive create_guard=-50.
This composite status does not identify SecKeychainCreate refusal. A Vault wrapper
pointer also differs from its owned SecKeychainRef; report them separately.
G0-04.2r freezes a dedicated no-create preflight branch: owned path guards and
read-only metadata getters/release, fixed numeric stages/statuses/booleans only.
Technical review precedes its single sandbox execution. No mutation retry,
escalation or preference restoration follows merely from the ambiguous -50.
Native CRUD/lock acceptance remains blocked pending the diagnostic disposition.
