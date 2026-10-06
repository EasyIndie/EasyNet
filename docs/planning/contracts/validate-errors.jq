# Shape/binding checker only; validate non-null operation with validate-operation.jq too.
def exact($fields): type == "object" and keys == ($fields | sort);
def matches($pattern):
  if type == "string" then test("\\A(" + $pattern + ")\\z") else false end;
def identifier: matches("[A-Za-z][A-Za-z0-9_-]{0,63}");
def registry: {
  "method-unsupported": ["revise-request", "local-rejection", "not-started"],
  "capability-unsupported": ["choose-supported-capability", "local-rejection", "not-started"],
  "capability-unknown": ["verify-capability", "local-rejection", "not-started"],
  "host-trust-required": ["verify-host-independently", "local-rejection", "not-started"],
  "hostkey-changed": ["review-hostkey-change", "local-rejection", "not-started"],
  "authentication-failed": ["review-credentials", "local-rejection", "not-started"],
  "permission-denied": ["review-permission", "local-rejection", "not-started"],
  "preflight-failed": ["resolve-preflight", "local-rejection", "not-started"],
  "secret-unavailable": ["resolve-secret-reference", "local-rejection", "not-started"],
  "remote-outcome-unknown": ["reconcile-same-operation", "remote-observation", "unknown"],
  "remote-failed": ["review-remote-failure", "remote-observation", "failed"]
};
try (
  exact(["schemaVersion","result","operation"]) and .schemaVersion == 1 and
  .result as $r | (registry[$r.code]) as $rule |
  ($r | exact(["binding","code","messageKey","nextAction","origin","remoteOutcome","evidenceRef"])) and
  $rule != null and $r.messageKey == ("error." + $r.code) and
  [$r.nextAction,$r.origin,$r.remoteOutcome] == $rule and
  ($r.binding | exact(["operationId","targetId","planHash"]) and
    ([.operationId,.targetId] | all(.[]; identifier)) and
    (.planHash | matches("sha256:[a-f0-9]{64}"))) and
  (if $r.origin == "local-rejection" then .operation == null and $r.evidenceRef == null
   else
    (.operation | exact(["schemaVersion","history"]) and .schemaVersion == 1 and
      (.history | type == "array" and length > 0)) and
    .operation.history as $h |
    all($h[]; {operationId,targetId,planHash} == $r.binding) and
    $h[-1].remoteState == $r.remoteOutcome and $h[-1].evidenceRef == $r.evidenceRef and
    (if $r.remoteOutcome == "failed" then
      ($r.evidenceRef | matches("receipt_[A-Za-z0-9_-]{1,64}"))
     else $r.evidenceRef == null or
      ($r.evidenceRef | matches("receipt_[A-Za-z0-9_-]{1,64}")) end)
   end)
) catch false
