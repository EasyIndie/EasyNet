# Framing checker only; project payloads through validate-operation.jq as well.
def exact($fields): type == "object" and keys == ($fields | sort);
def matches($pattern):
  if type == "string" then test("\\A(" + $pattern + ")\\z") else false end;
def identifier: matches("[A-Za-z][A-Za-z0-9_-]{0,63}");
def snapshot:
  exact(["operationId","targetId","planHash","remoteState","localState","action","evidenceRef"]) and
  ([.operationId,.targetId] | all(.[]; identifier)) and
  (.planHash | matches("sha256:[a-f0-9]{64}")) and
  (.remoteState | matches("planned|running|unknown|succeeded|failed|cancelled")) and
  (.localState | matches("connected|disconnected|exited")) and
  (.action | matches("create|start|observe|disconnect|local-exit|cancel-request|reconcile|retry")) and
  (.evidenceRef == null or (.evidenceRef | matches("receipt_[A-Za-z0-9_-]{1,64}"))) and
  (if (.remoteState | matches("succeeded|failed|cancelled")) then .evidenceRef != null else true end);
def event:
  exact(["seq","type","payload"]) and
  (.seq | type == "number" and . == floor and . >= 1 and . <= 9007199254740991) and
  (.type | matches("operation[.]snapshot")) and
  (.payload | snapshot);
try (
  exact(["schemaVersion","events"]) and .schemaVersion == 1 and
  (.events | . as $e | type == "array" and length > 0 and all(.[]; event) and
    all(range(0; length);
      $e[.].seq == . + 1 and
      ($e[.].payload | [.operationId,.targetId,.planHash]) ==
      ($e[0].payload | [.operationId,.targetId,.planHash])))
) catch false
