# sing-box v1.14.2 native engine source facts

Status: **scope-exceeded; provenance mechanically checked; config planned**. These are bounded source notes only;
no config is approved or frozen. Sources are the official
`SagerNet/sing-box` `v1.14.2` tag. The exact option Contents response was 53,383 bytes
(under 64 KiB); it listed the files below. Its URL is
https://api.github.com/repos/SagerNet/sing-box/contents/option?ref=v1.14.2.

## Bounded source ledger

| Tag path | Blob ID | Bytes | SHA-256 | Relevant tagged lines |
|---|---|---:|---|---|
| `option/inbound.go` | `7bca5653ee4b2ccf10a360b6de04adb41f397bc7` | 6,404 | `0fb33edaa67b44eaf63017e1077eeae0daa8a8e12a7f007efb16fa631983188d` | [L79-L95](https://github.com/SagerNet/sing-box/blob/v1.14.2/option/inbound.go#L79-L95) |
| `option/route.go` | `39f3cfb9d9a1d63abe33cd78b2ca5010ff312007` | 2,329 | `43998a79dbf8e6a5fa5fe3d5ca2f5ccbbcf550a554559e232c98b2b52f02edb7` | [source](https://github.com/SagerNet/sing-box/blob/v1.14.2/option/route.go) |
| `option/outbound.go` | `4590b48d0bb2b7a62e2abfde1c24761af856ef82` | 7,497 | `811dfffc1f9bbbbc05c3e7e0afcfe291a5706e357558939d87b0a2a600332b12` | [source](https://github.com/SagerNet/sing-box/blob/v1.14.2/option/outbound.go) |
| `option/dns.go` | `1180a6227a75022f5ab11ea7b29ee96f82cd5ebe` | 7,139 | `eebf249cbc4bf6c054bbe5d78b88c894e3c66e1be1c1eea8c618f22603fdaa1d` | [source](https://github.com/SagerNet/sing-box/blob/v1.14.2/option/dns.go) |
| `option/rule.go` | `15f86a4d62fbd60dd0d47fd4e8cf1135d229f9f2` | 13,365 | `4db39462c6460dc97610ee115ff589a5913c8f4332f442011aac3ed9fdcdc0b7` | [L140-L161](https://github.com/SagerNet/sing-box/blob/v1.14.2/option/rule.go#L140-L161), [L189-L203](https://github.com/SagerNet/sing-box/blob/v1.14.2/option/rule.go#L189-L203) |
| `option/rule_action.go` | `ae05200430bfaca77a436ef28f38316f149006b7` | 14,248 | `8d1d7b69ec85b0f79769df6f9d7e993c0ace16cc3950cefe06d9edf934a933ee` | [L18-L27](https://github.com/SagerNet/sing-box/blob/v1.14.2/option/rule_action.go#L18-L27), [L174-L187](https://github.com/SagerNet/sing-box/blob/v1.14.2/option/rule_action.go#L174-L187), [L291-L319](https://github.com/SagerNet/sing-box/blob/v1.14.2/option/rule_action.go#L291-L319) |
| `option/direct.go` | `a11c45e9805973210190abf1881ee0dd4bb09426` | 1,250 | `5b394eba65e7f80d5874fa7ef172ef2fb4a3bf24a5172e6d6dc2c290a429e567` | [L17-L25](https://github.com/SagerNet/sing-box/blob/v1.14.2/option/direct.go#L17-L25) |

The source lookup exceeded the four-file cap: the initial dispatch included CLI background
that did not match the final card's narrower field scope; clarification caused a source-set
reselection, and the budget was not reset. This was a coordination and C-counting error.
Four files were fetched first, then three more while changing the candidate set. All seven
entries are recorded above; aggregate
retrieved source bytes were 52,232. The four files used for field facts are inbound.go,
rule.go, rule_action.go, and direct.go (35,267 bytes). The other three were not used as
evidence. The text was inspected inertly; no source was imported or executed. No further
source or directory lookup was made. Root checked all seven retained files' byte counts,
SHA256 and Git blob identities against this ledger; no source was executed. This check does
not erase the scope failure or approve config/runtime semantics. No architecture disposition is made.

## Source-confirmed facts

- Shared `ListenOptions` defines JSON `listen` as `*badoption.Addr` and `listen_port` as
  `uint16`. It does not establish the SOCKS inbound discriminator, SOCKS-specific defaults,
  or whether a numeric IPv4 literal is the exact accepted representation.
- Default route rules expose `ip_cidr` as a list of strings and `port` as a list of
  `uint16`; the combined `DefaultRule` contains the match fields and a `RuleAction`.
  This supports a numeric destination IP/CIDR plus port field proposal, but does not prove
  exact match semantics or the echo fixture’s config acceptance.
- Rule actions list `route`, `direct`, `reject` (among other variants). A route action has
  an optional `outbound` reference; direct action has dialer options; reject has optional
  method (`default`, `drop`, `reply`) and `no_drop`. This supports action names, not
  unmatched-route behavior or precedence/default semantics.
- `option/direct.go` identifies direct outbound options; its decoder rejects nonempty
  override address/port as removed since1.13 ([L29-L38](https://github.com/SagerNet/sing-box/blob/v1.14.2/option/direct.go#L29-L38)).
  Those declarations cannot be treated as usable fields. No direct outbound tag/config is frozen here.
- No CLI command/argv, SOCKS-specific option source, route default source, runtime behavior,
  or executable acceptance was inspected.

## Config not frozen; finite gaps

- DNS/upstream/default resolver behavior: not determined. The exact SOCKS inbound type and
  its defaults: not determined. Unmatched-route behavior and precedence: not determined.
- Whether omitting DNS is safe for the numeric SOCKS CONNECT fixture, and whether TUN or
  system proxy effects occur: not determined.
- Do not infer a complete config from the listed fields. The numeric loopback SOCKS-to-echo
  with default reject remains unproven; implementation/runtime are not ready.
