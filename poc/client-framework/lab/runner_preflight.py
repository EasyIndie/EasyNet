"""Transport reviewed diagnostic to a disposable GitHub macOS image, once."""
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys

HASHES = {
    "isolate.py": "3bc47c022eb6bf10004372cc4021e0d692720e81b318d5dd0cffb54b18d2522c",
    "mapping-fixture.sb": "1dfc6055110b29f06ccd2026eb230433cd5ca6da9be2354b2c43fb88efba0595",
    "mapping_diag.py": "3918c9408f323cc4390465717e151d841b54a524bb83246185be1d6e48cba59b",
    "mapping_diag_test.py": "552bb9eb486967cc1377db6f458ff35f371a836c13f5172177342cc1c1309f1f",
    "mapping_main_test.py": "09f9b773dc949656ce3769e3449e05123717e5c8eb1247c429bb841091127c72",
    "fixture.sb": "b554c29d574b6c1852f7facbdbd8e4fe10af7864ec64637a3191055e2e8e3c82",
}


def main():
    if (sys.argv[1:] or sys.platform != "darwin" or platform.machine() != "arm64"
            or os.getuid() == 0 or sys.version_info[:2] != (3, 14)
            or not hasattr(os, "waitid") or not hasattr(os, "WNOWAIT")
            or os.environ.get("GITHUB_ACTIONS") != "true"
            or os.environ.get("GITHUB_REPOSITORY") != "EasyIndie/EasyNet"
            or os.environ.get("GITHUB_REF") != "refs/heads/codex/feature/self-hosted-byos-byoc"):
        print("FAIL: fixed unprivileged GitHub macOS arm64 Python3.14 target required")
        return 1
    directory = Path(__file__).resolve().parent
    executable = Path(sys.executable).resolve(strict=True)
    digest = hashlib.sha256(executable.read_bytes()).hexdigest()
    # Host-image provenance is the trust baseline, not an external Python pin.
    print(json.dumps({"target": "github-macos-15-arm64", "python": platform.python_version(),
                      "python_sha256": digest, "macos": platform.mac_ver()[0],
                      "kernel": platform.release(), "toolchain": "observed image baseline"}))

    def verify():
        for name, expected in HASHES.items():
            if hashlib.sha256((directory / name).read_bytes()).hexdigest() != expected:
                raise ValueError("reviewed source hash changed")
        if hashlib.sha256(executable.read_bytes()).hexdigest() != digest:
            raise ValueError("observed executable hash changed")

    environment = {"PATH": "/usr/bin:/bin", "LC_ALL": "C"}
    for name in ("HOME", "CODEX_HOME"):
        if name in os.environ:
            environment[name] = os.environ[name]
    for name in ("mapping_diag_test.py", "mapping_main_test.py", "mapping_diag.py"):
        verify()
        result = subprocess.run([str(executable), "-I", "-B", str(directory / name)],
                                stdin=subprocess.DEVNULL, capture_output=True,
                                text=True, env=environment)
        verify()
        print(json.dumps({"command": name, "exit_code": result.returncode,
                          "reviewed_hashes": "unchanged before/after"}))
        if name == "mapping_diag.py":
            # This exact hashed driver emits only fixed labels and bounded fields.
            print(result.stdout, end="")
        if result.returncode != 0:
            print("STOP: no retry; retained guest fixture ends with VM teardown")
            return 1
    print("PASS: A-D slice only; full isolation/SDK/GUI gates not accepted")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception:
        print("FAIL: preflight guard/execution; no further launch")
        raise SystemExit(1)
