# Profile descriptor — draft v1

G0-03.1c offline research draft, pending joint ADR/high review. This is ordinary
controller inventory, not a native exporter, client renderer or production importer.
The envelope has exactly `schemaVersion: 1` and a nonempty `profiles` array.
Each descriptor has exactly the fields below; unknown fields fail at every level.

| Field | Restriction / meaning |
|---|---|
| `id` | Unique stable profile identity: 1–64 ASCII letters/digits/underscore/hyphen, starting with a letter. |
| `revision` | Positive integer identifying a descriptor revision; no automatic migration or rollback. |
| `targetId` | Same identifier syntax; reference to ServerTarget `id`, never SSH credentials or a host identity. |
| `runtimeId`, `protocolId`, `format` | Must match one of the exact tuples below. |
| `endpoint` | Exactly `host`, `port`; DNS/canonical IPv4 and integer port 1–65535. |
| `configRef` | Opaque `config_` identifier followed by 1–64 ASCII letters/digits/underscore/hyphen; separately stored secret configuration. |

| runtimeId | protocolId | format |
|---|---|---|
| `hysteria2-native` | `hysteria2` | `hysteria2-native-config` |
| `amneziawg-native` | `amneziawg` | `amneziawg-native-config` |

These tuples bind draft format identities to G0-03.1b runtime identities; they do
not claim native payload validation. Its `exportNative` is **unknown** for both
runtimes. A passing descriptor is an offline contract example only. Production
export must refuse unknown capability; unsupported runtime/protocol/format pairs
are rejected here without fallback. AWG is not native WireGuard or sing-box native
format; legacy module `wireguard` and renderer labels grant no parity.

Endpoint syntax reuses ServerTarget draft v1: DNS labels are ASCII, at least two
labels, at most 253 characters; numeric/hex dotted hosts must validate as canonical
four-octet IPv4, octets 0–255 without leading zero. IPv6/IDN/aliases remain pending.
Endpoints describe client connection destinations, not SSH endpoints; they need
not equal target SSH hosts. All restricted strings reject control characters.

Ordinary inventory contains no password, token, key, URI, native payload or secret
file path. A separate reviewed secret store must resolve configRef and bind its
content to this exact target/runtime/protocol/format/revision before any use.
This checker checks reference syntax only: it cannot prove reference existence,
ownership, secret absence inside an opaque identifier, or target inventory
resolution. Future consumers must reject unresolved/mismatched references.
Legacy metadata v1 and its existing mode-600 file remain intact, including existing
client URI/config consumers; this draft does not redact historical CLI outputs.

Run `jq -e -f docs/planning/contracts/validate-profile.jq` on the example envelope:
true/exit 0 means draft shape/tuple acceptance, false/nonzero means rejection.
No secret is retrieved, payload generated, endpoint contacted or runtime invoked.
Duplicate JSON-key detection, secret lifecycle, real client acceptance and secure
export channels remain unimplemented and require separate review.
