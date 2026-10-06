# Offline draft descriptor checker; never resolves a secret or invokes exportNative.
def exact($fields): type == "object" and keys == ($fields | sort);
def matches($pattern):
  if type == "string" then test("\\A(" + $pattern + ")\\z") else false end;
def identifier: matches("[A-Za-z][A-Za-z0-9_-]{0,63}");
# Keep host syntax identical to ServerTarget draft v1; IPv6 remains pending.
def ipv4:
  split(".") | length == 4 and all(.[];
    matches("0|[1-9][0-9]{0,2}") and (tonumber <= 255));
def hostname:
  if type == "string" then
    if (split(".") | all(.[]; matches("[0-9]*|0[xX][A-Fa-f0-9]+"))) then ipv4 else
      length <= 253 and (split(".") | length >= 2 and all(.[];
        matches("[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?")))
    end
  else false end;
def positive_integer: type == "number" and . == floor and . >= 1;
def endpoint:
  exact(["host", "port"]) and (.host | hostname) and
  (.port | positive_integer and . <= 65535);
def profile:
  exact(["id", "revision", "targetId", "runtimeId", "protocolId", "format", "endpoint", "configRef"]) and
  ([.id, .targetId] | all(.[]; identifier)) and
  (.revision | positive_integer) and (.endpoint | endpoint) and
  (.configRef | matches("config_[A-Za-z0-9_-]{1,64}")) and
  ([.runtimeId, .protocolId, .format] ==
    ["hysteria2-native", "hysteria2", "hysteria2-native-config"] or
   [.runtimeId, .protocolId, .format] ==
    ["amneziawg-native", "amneziawg", "amneziawg-native-config"]);
try (
  exact(["schemaVersion", "profiles"]) and .schemaVersion == 1 and
  (.profiles | type == "array" and length > 0 and all(.[]; profile) and
    ((map(.id) | unique | length) == length))
) catch false
