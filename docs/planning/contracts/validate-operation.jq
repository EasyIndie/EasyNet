# Reference history checker; no remote execution, receipt resolution or lock.
def exact($fields): type == "object" and keys == ($fields | sort);
def matches($pattern):
  if type == "string" then test("\\A(" + $pattern + ")\\z") else false end;
def identifier: matches("[A-Za-z][A-Za-z0-9_-]{0,63}");
def terminal: matches("succeeded|failed|cancelled");
def snapshot:
  exact(["operationId","targetId","planHash","remoteState","localState","action","evidenceRef"]) and
  ([.operationId,.targetId] | all(.[]; identifier)) and
  (.planHash | matches("sha256:[a-f0-9]{64}")) and
  (.remoteState | matches("planned|running|unknown|succeeded|failed|cancelled")) and
  (.localState | matches("connected|disconnected|exited")) and
  (.action | matches("create|start|observe|disconnect|local-exit|cancel-request|reconcile|retry")) and
  (.evidenceRef == null or (.evidenceRef | matches("receipt_[A-Za-z0-9_-]{1,64}"))) and
  (if (.remoteState | terminal) then .evidenceRef != null else true end);
def transition($before; $after):
  ($after | [.operationId,.targetId,.planHash]) == ($before | [.operationId,.targetId,.planHash]) and
  (if $after.action == "disconnect" or $after.action == "local-exit" then
    $after.localState == (if $after.action == "disconnect" then "disconnected" else "exited" end) and
    (if ($before.remoteState | terminal) then
      $after.remoteState == $before.remoteState and $after.evidenceRef == $before.evidenceRef
    else $after.remoteState == "unknown" and $after.evidenceRef == null end)
  elif $after.action == "cancel-request" then
    ($before.remoteState | matches("running|unknown")) and
    $after.remoteState == $before.remoteState and $after.localState == $before.localState and
    $after.evidenceRef == $before.evidenceRef
  else $after.localState == "connected" and $after.evidenceRef != null and
    (if $after.action == "start" or $after.action == "retry" then
      $before.remoteState == "planned" and $after.remoteState == "running" and
      ($after.action == "start" or $before.action == "reconcile")
    elif $after.action == "reconcile" then $before.remoteState == "unknown"
    elif $after.action == "observe" then
      ($before.remoteState == "running" and ($after.remoteState | matches("running|succeeded|failed|cancelled"))) or
      (($before.remoteState | terminal) and $after.remoteState == $before.remoteState)
    else false end)
  end);
try (
  exact(["schemaVersion","history"]) and .schemaVersion == 1 and
  (.history | type == "array" and length > 0 and all(.[]; snapshot) and
    (.[0] | .remoteState == "planned" and .localState == "connected" and
      .action == "create" and .evidenceRef == null) and
    . as $h | all(range(1; length); transition($h[. - 1]; $h[.])))
) catch false
