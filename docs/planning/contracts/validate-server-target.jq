# Restricted draft-v1 example checker; no connection or trust side effects.
def exact($fields):
  type == "object" and (keys == ($fields | sort));
def matches($pattern):
  if type == "string" then test("\\A(" + $pattern + ")\\z") else false end;
def identifier:
  matches("[A-Za-z][A-Za-z0-9_-]{0,63}");
def ipv4:
  split(".") | length == 4 and all(.[];
    matches("0|[1-9][0-9]{0,2}") and (tonumber <= 255));
def hostname:
  if type == "string" then
    if (split(".") | all(.[]; matches("[0-9]*|0[xX][A-Fa-f0-9]+"))) then ipv4 else
      length <= 253 and
      (split(".") | length >= 2 and all(.[];
        matches("[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?")))
    end
  else false end;
def port:
  if type == "number" then . == floor and . >= 1 and . <= 65535
  else false end;
def ssh:
  exact(["host", "port", "user"]) and (.host | hostname) and
  (.port | port) and (.user | matches("[a-z_][a-z0-9_-]{0,31}"));
def privilege:
  if type != "object" then false
  elif .mode == "effective-root" then exact(["mode"])
  elif .mode == "sudo" then
    exact(["mode", "sudoPolicy"]) and .sudoPolicy == "noninteractive-root"
  else false end;
def target:
  if type != "object" then false else
    (if .kind == "ExistingServer" then
       exact(["id", "kind", "ssh", "credentialRef", "privilege"])
     elif .kind == "CloudServer" then
       exact(["id", "kind", "ssh", "credentialRef", "privilege", "cloud"]) and
       (.cloud | exact(["provider", "resourceId"]) and
         (.provider | identifier) and (.resourceId | identifier))
     else false end) and
    (.id | identifier) and (.ssh | ssh) and (.privilege | privilege) and
    (.credentialRef | matches("cred_[A-Za-z0-9_-]{1,64}"))
  end;
try (
  exact(["schemaVersion", "targets"]) and .schemaVersion == 1 and
  (.targets | type == "array" and length > 0 and all(.[]; target) and
    ((map(.id) | unique | length) == length))
) catch false
