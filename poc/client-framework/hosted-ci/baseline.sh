#!/bin/bash
# Static proposal: root replaces the reviewed hash only after source acceptance.
set -u
refuse() {
    printf '%s\n' '{"schema":1,"phase":"bootstrap","result":"refused","error":"source","cleanup":"unknown","descendants":"not-proven","external-effects":"trusted-vendor-not-denied","vm-cleanup":"provider-managed-unverified"}'
    exit 1
}
[[ $# == 0 ]] || refuse
observer="${BASH_SOURCE[0]%/*}/observe.py"
expected='79394936e61caa7b7afb186d42be4991cf85fd2cb04560809606c28d68c00b5f'
[[ $expected =~ ^[a-f0-9]{64}$ ]] || refuse
[[ -f $observer && ! -L $observer ]] || refuse
[[ -x /usr/bin/python3 ]] || refuse
actual=$(/usr/bin/env -i PATH=/usr/bin:/bin LANG=C LC_ALL=C /usr/bin/shasum -a 256 "$observer" 2>/dev/null) || refuse
[[ ${actual%% *} == "$expected" ]] || refuse
exec /usr/bin/env -i PATH=/usr/bin:/bin LANG=C LC_ALL=C \
    ImageOS="${ImageOS-}" ImageVersion="${ImageVersion-}" \
    /usr/bin/python3 -I "$observer" 2>/dev/null
