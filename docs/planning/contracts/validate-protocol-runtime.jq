# Draft example checker only; never calls a driver or executes a method.
def exact($fields): type == "object" and keys == ($fields | sort);
def identifier:
  if type == "string" then test("\\A[A-Za-z][A-Za-z0-9_-]{0,63}\\z") else false end;
def methods: ["describe", "install", "exportNative", "exportSingboxNative"];
def capability_names: methods + ["nativeWireguard"];
def capability:
  exact(["state", "evidence"]) and
  ((.state == "supported" and .evidence == "source-identity") or
   (.state == "unsupported" and .evidence == "format-boundary") or
   (.state == "unknown" and .evidence == "unverified"));
def state($name; $value): .capabilities[$name].state == $value;
def runtime:
  exact(["runtimeId", "protocolId", "moduleId", "capabilities"]) and
  ([.runtimeId, .protocolId, .moduleId] | all(.[]; identifier)) and
  (.capabilities | exact(capability_names) and all(.[]; capability)) and
  state("describe"; "supported") and state("install"; "unknown") and
  state("exportNative"; "unknown") and state("nativeWireguard"; "unsupported") and
  (if .runtimeId == "hysteria2-native" then
     .protocolId == "hysteria2" and .moduleId == "hysteria2" and
     state("exportSingboxNative"; "unknown")
   elif .runtimeId == "amneziawg-native" then
     .protocolId == "amneziawg" and .moduleId == "wireguard" and
     state("exportSingboxNative"; "unsupported")
   else false end);
def shape:
  exact(["schemaVersion", "runtimes", "request"]) and .schemaVersion == 1 and
  (.runtimes | type == "array" and length > 0 and all(.[]; runtime) and
    ((map(.runtimeId) | unique | length) == length)) and
  (.request | exact(["runtimeId", "targetId", "method"]) and
    (.runtimeId | identifier) and (.targetId | identifier) and
    (.method as $method | methods | index($method) != null));
. as $document | [try shape catch false] |
if .[0] then $document |
  .request as $request |
  [.runtimes[] | select(.runtimeId == $request.runtimeId)] as $selected |
  if ($selected | length) != 1 then false else
    $selected[0].capabilities[$request.method].state |
    if . == "supported" then true
    elif . == "unsupported" then error("capability-unsupported")
    else error("capability-unknown") end
  end
else false end
