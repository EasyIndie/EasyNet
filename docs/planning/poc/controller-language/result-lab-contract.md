# Candidate result/CLI packaging lab v1

Compare Go A and Rust B with this same bounded, redacted JSON format. This is
PoC interoperability, not the application Operation/history contract, metadata
v1, an authenticated receipt, durable journal or a production language decision.

One flat object has exactly six fields, all non-null:

| Field | Constraint |
|---|---|
| kind | literal `easynet-lab-result` |
| schemaVersion | integer JSON token 1; no fraction/exponent/coercion |
| operationId | 1–64 ASCII letters/digits/underscore/hyphen, matching existing lab Run; production IDs have a separate contract |
| outcome | `not-dispatched`, `unknown`, `fixture-complete-observed` |
| ownerRetained | boolean; false for not-dispatched, true for unknown and fixture-complete-observed |
| outputBytes | lexical `0` or `[1-9][0-9]*`, value ≤4096; no negative zero; 0 for not-dispatched |

Input is at most 4096 bytes and valid UTF-8. Reject missing/extra/null/wrong-type
fields, duplicates (including escaped-equivalent keys), case aliases, compound
values, unsupported versions, malformed/trailing/second JSON values and oversized
input. Never coerce unknown into a terminal result or release ownership after an
observed fixture completion. No raw stdout, credentials, paths, configuration or
receipt references are serialized: summarize existing typed Result using byte
length only. This does not authenticate caller-supplied summaries.

Go exact interfaces: `Summarize(Result) (LabRecord, error)`,
`DecodeLabRecord(io.Reader) (LabRecord, error)`, and
`EncodeLabRecord(io.Writer, LabRecord) error`. LabRecord fields/tags are
Kind string/kind, SchemaVersion int/schemaVersion, OperationID string/operationId,
Outcome string/outcome, OwnerRetained bool/ownerRetained, OutputBytes int/outputBytes.
Summarize validates independently; a rejected Run may carry an invalid caller ID.
Any summarization/decoding error returns a zero LabRecord. Invalid records return a fixed ErrInvalidLabRecord;
reader/writer failure or short write returns fixed ErrLabRecordIO, never raw
parser/data/I/O exception text. Validate before encoding; invalid input writes
nothing. A failed output write may be partial and cannot claim atomic delivery.
Equivalent Rust behavior is required before the language comparison.

A later small CLI reads one bounded stdin record and emits normalized JSON;
errors use fixed messages and nonzero exit, without echoing input/error details.
Owned subprocess tests exercise real binaries with finite limits. Record host
Mach-O/build/link/signature facts and artifact hashes/sizes. Ad-hoc signing is
not Developer ID, notarization, installer/update delivery or platform support.
Do not run SSH/Keychain through this CLI or publish official versions/releases.

Sol high reviewed the frozen semantics and cross-language numeric grammar;
this contract governs only the bounded candidate PoC, not production records.
