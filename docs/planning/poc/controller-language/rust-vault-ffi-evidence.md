# Rust vault FFI facts (source inspection only)

Scope: reviewed C helper/header plus installed SDK typedefs; no Rust ABI, layout, compile, link, or native runtime validation was performed. This is evidence input for a later Sol high design freeze, not a language or security decision.

## Pinned local facts

- `native.c` SHA-256: `6c2b3e83f3c32f3baa248b4253b019976a154421353a7cc8637dd9d4e51c0dbc`.
- `native.h` SHA-256: `89b5cd41f79adc02520c9fbabf83149f42c0d92705144e90babc84d2069aa771`.
- Installed macOS SDK: 27.0; `xcrun --show-sdk-path` selected `MacOSX.sdk` in Xcode 27.0.0.
- `clang`: Apple clang 21.0.0 (`clang-2100.3.34.2`), arm64-apple-darwin27.0.0.
- `ar`: `xcrun --find ar` resolves to the selected Xcode toolchain; `ar --version` is unsupported and prints usage.
- `rustc` is not on PATH, but the existing task-owned compiler `/tmp/easynet-poc-toolchains/rust/bin/rustc` reports `rustc 1.99.0 (b940084d7 2026-09-28)` (root read-only verification). Availability does not prove standalone link acceptance.
- SDK headers inspected: Security `SecBase.h`; CoreFoundation `CFBase.h`. They define `SecKeychainRef` as a pointer to `__SecKeychain`, `UInt32` as unsigned int, `OSStatus` as `SInt32`, `CFIndex` as signed long on this target, and `CFTypeRef` as const void pointer. These typedefs do not establish Rust ABI layout.

## Exported C surface and ownership facts

All pointer arguments are C pointers. The source establishes call behavior and ownership below; the proposed Rust types are candidates only.

| C declaration | Candidate Rust shape | Source ownership / ABI note |
|---|---|---|
| `typedef struct Vault Vault;` | opaque `c_void` handle | Internal fields are not exported. |
| `typedef struct { bool path_guard_ok; int stage; OSStatus status; } VaultProbe;` | `#[repr(C)]` candidate with bool, c_int, i32 | Returned by value; struct layout and return ABI are **unverified**. |
| `VaultProbe vault_probe(const char *path);` | `*const c_char` → candidate struct | Path is borrowed, NUL-terminated; probe makes no keychain changes. |
| `bool vault_has_keychain(Vault *vault);` | opaque handle → candidate bool | Handle is borrowed. C bool ABI is **unverified**. |
| `OSStatus vault_create(const char *path, const void *password, UInt32 length, Vault **out, bool *metadataUnchanged);` | path/password pointers, u32 length, out-handle and bool pointers | Path/password borrowed for call. Initializes outputs; may assign an allocated wrapper before a later failure. If `*out != NULL`, caller must call `vault_release` exactly once even when status is nonzero. |
| `OSStatus vault_unchanged(Vault *vault, bool *equal);` | handle + out bool | Handle borrowed; output is caller-owned storage. Reads default/search-list snapshot. |
| `OSStatus vault_unlock(Vault *vault, const void *password, UInt32 length);` | handle + borrowed bytes + u32 | Does not retain password pointer. |
| `OSStatus vault_is_unlocked(Vault *vault, bool *unlocked);` | handle + out bool | Handle borrowed; output storage caller-owned. |
| `OSStatus vault_add(Vault *vault, const void *bytes, UInt32 length);` | handle + borrowed bytes + u32 | Input bytes consumed during call; helper creates/releases its CFData. |
| `OSStatus vault_update(Vault *vault, const void *bytes, UInt32 length);` | handle + borrowed bytes + u32 | Same input lifetime as add. |
| `OSStatus vault_read_equals(Vault *vault, const void *bytes, UInt32 length, bool *equal, bool *dataReturned);` | handle + borrowed bytes + u32 + out bools | Helper releases returned CF object; does not transfer secret bytes. |
| `OSStatus vault_delete(Vault *vault);` | handle | Handle borrowed; helper releases query object. |
| `OSStatus vault_lock(Vault *vault);` | handle | Handle borrowed. |
| `OSStatus vault_read_status(Vault *vault, bool *dataReturned, bool *queried);` | handle + out bools | Helper releases query/result objects; `queried` becomes true immediately before native query call. |
| `void vault_release(Vault *vault);` | opaque handle | Null-safe; releases owned keychain ref, baseline path allocations, and wrapper. |

Candidate Rust mappings are `OSStatus` → `i32`, `UInt32` → `u32`, opaque pointers → `*mut c_void`, C paths → `*const c_char`, and C `bool` → a C-ABI bool candidate. `VaultProbe` and C bool mappings require a dedicated ABI/layout check before use; no such check was run.

## Guard and metadata behavior observed in source

- `private_path` rejects null paths and effective UID 0; accepts only `/tmp/easynet-vault-lab-*` or `/private/tmp/easynet-vault-lab-*` with direct `fixture.keychain` child and a restricted parent-name alphabet.
- Parent must be an euid-owned directory with exact mode 0700. `realpath` must resolve to a direct child under `/private/tmp/easynet-vault-lab-*`; target keychain path must not exist. These are source predicates, not executed path tests.
- `vault_create` snapshots default keychain and search-list paths, disables process user interaction, calls `SecKeychainCreate` with `promptUser=false`, and compares metadata after create. The source does not write preferences or delete a keychain.
- Item queries set `kSecUseAuthenticationUI = kSecUseAuthenticationUIFail`; add selects the owned keychain, and read/update/delete constrain search to the owned ref. Fixed service/account values are synthetic.
- `vault_release` releases the owned reference and in-memory snapshots. This source review is not runtime evidence that OS behavior matches the contract.

## Standalone build proposal (not executed)

Keep `poc/controller-language/rust/Cargo.toml` and its SSH dependency graph unchanged. A later isolated fixture may compile only `native.c` with the selected SDK using Xcode `clang`, archive `native.o` with the selected `ar` into `libvaultnative.a`, then invoke `rustc` on a minimal FFI harness with `-L native=<archive-dir> -l static=vaultnative -l framework=Security -l framework=CoreFoundation`. Exact flags, target/deployment settings, Rust linker acceptance, symbol linkage, and ownership behavior remain **unverified** until a separately frozen ABI/build task. No implementation or framework choice is implied.
