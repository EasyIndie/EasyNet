"""Fixed mapping diagnostic; importing performs no fixture or native I/O."""
import importlib.util
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import time
import uuid

FIELDS = ("returncode", "timed_out", "reaped", "elapsed_s", "stdout_count",
          "stderr_count", "phase", "primary_class", "primary_errno", "cleanup_class",
          "cleanup_errno", "waitid_exit_observed", "group_check", "owned_pid",
          "leader_wait_completed", "signals", "errors", "stdout_eof", "stderr_eof",
          "stdout_closed", "stderr_closed", "helper_wait_completed")


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def healthy(result, expected, stderr=b"", returncode=0):
    """Lifecycle success alone is insufficient: rc and exact bytes also matter."""
    flags = ("reaped", "waitid_exit_observed", "leader_wait_completed",
             "helper_wait_completed", "stdout_eof", "stderr_eof",
             "stdout_closed", "stderr_closed")
    return (all(result[name] is True for name in flags)
            and result["timed_out"] is False and result["returncode"] == returncode
            and 0 <= result["elapsed_s"] < 1
            and result["group_check"] == "sole-zombie"
            and type(result["owned_pid"]) is int and result["owned_pid"] > 0
            and result["primary_class"] == result["cleanup_class"] == "none"
            and result["primary_errno"] is None and result["cleanup_errno"] is None
            and result["errors"] == [] and result["signals"] == []
            and result["stdout"] == expected and result["stderr"] == stderr
            and result["stdout_count"] == len(expected) <= 8192
            and result["stderr_count"] == len(stderr) <= 8192)


def sequence(probe, expected, decoy_nonce, decoy_path, end, clock, emit):
    """One fixed A/B/C/D attempt; exact permission errno text is mandatory."""
    denial = b"cat: " + str(decoy_path).encode() + b": Operation not permitted\n"
    for label, case in zip("ABCD", ("direct-eof", "sandbox-eof", "allowed-read", "denied-read")):
        try:
            budget = min(2, end - clock() - 0.3)
            require(budget > 0.35, "mapping budget exhausted")
            result = probe(case, budget)
            wanted = expected if label == "C" else b""
            stderr = denial if label == "D" else b""
            matched = (result["stdout"] == wanted and result["stderr"] == stderr
                       and decoy_nonce not in result["stdout"] + result["stderr"])
            passed = (healthy(result, wanted, stderr, 1 if label == "D" else 0)
                      and matched and result["elapsed_s"] <= budget and clock() < end)
            record = {name: result[name] for name in FIELDS}
            record.update(case=label, expected_match=matched,
                          outcome="pass" if passed else "unknown")
            emit(record)
            if not passed:
                return False
        except Exception:
            emit({"case": label, "outcome": "unknown", "expected_match": False})
            return False
    return True


def clean_fixture(module, allowed, end):
    require(time.monotonic() < end, "cleanup deadline exhausted")
    require(not module._live, "unreaped child blocks cleanup")
    entries = module.check_fixture(allowed)
    # Complete frozen manifest first; only known entries, never recursive removal.
    files = [path for path, value in entries.items() if stat.S_ISREG(value[3])]
    for path in files:
        require(time.monotonic() < end, "cleanup deadline exhausted")
        require(module._identity(path) == entries[path], "cleanup identity mismatch")
        require(time.monotonic() < end, "cleanup deadline exhausted")
        path.unlink()
    root = allowed.parent
    for directory in (allowed, root / "decoy", root):
        require(time.monotonic() < end, "cleanup deadline exhausted")
        require(module._identity(directory, True) == entries[directory],
                "cleanup directory identity mismatch")
        require(time.monotonic() < end, "cleanup deadline exhausted")
        directory.rmdir()
    require(time.monotonic() < end, "final deadline exhausted")


def failure_summary(allocated, cleanup_started):
    if cleanup_started:
        return "FAIL/unknown: cleanup started; remaining fixture state unknown"
    if allocated:
        return "FAIL/unknown: pre-cleanup fixture retained; no further launch"
    return "FAIL/unknown: no fixture allocated; no further launch"


def main():
    start = time.monotonic()
    end = start + 12
    allocated = cleanup_started = False
    if sys.argv[1:] or sys.platform != "darwin" or os.getuid() == 0:
        print('FAIL/unknown: exact no-argument unprivileged Darwin driver required')
        return 1
    try:
        path = Path(__file__).absolute().parent / "isolate.py"
        spec = importlib.util.spec_from_file_location("mapping_isolate", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        require(time.monotonic() < end, "setup deadline exhausted")
        root = Path(tempfile.mkdtemp(prefix="easynet-g0-06-isolate-", dir="/private/tmp"))
        allocated = True
        require(time.monotonic() < end, "setup deadline exhausted")
        os.chmod(root, 0o700)
        nonces = {}
        for name in ("allowed", "decoy"):
            require(time.monotonic() < end, "setup deadline exhausted")
            directory = root / name
            directory.mkdir(mode=0o700)
            require(time.monotonic() < end, "setup deadline exhausted")
            os.chmod(directory, 0o700)
            require(time.monotonic() < end, "setup deadline exhausted")
            fd = os.open(directory / "seed", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "wb") as stream:
                require(time.monotonic() < end, "setup deadline exhausted")
                os.fchmod(stream.fileno(), 0o600)
                nonce = uuid.uuid4().hex.encode()
                require(time.monotonic() < end, "setup deadline exhausted")
                stream.write(nonce)
            nonces[name] = nonce
        allowed = root / "allowed"
        require(time.monotonic() < end, "setup deadline exhausted")
        module.freeze_fixture(allowed)
        setup_elapsed = time.monotonic() - start
        require(setup_elapsed < 4, "combined setup/finish budget exhausted")
        profile = path.parent / "mapping-fixture.sb"
        passed = sequence(
            lambda case, budget: module.run_mapping_probe(profile, allowed, case, budget),
            nonces["allowed"], nonces["decoy"], root / "decoy/seed", end, time.monotonic,
            lambda record: print(json.dumps(record, sort_keys=True)))
        require(passed, "mapping outcome unqualified")
        finish_end = min(end, time.monotonic() + 4 - setup_elapsed)
        require(time.monotonic() < finish_end, "combined setup/finish budget exhausted")
        cleanup_started = True
        clean_fixture(module, allowed, finish_end)
        print("PASS: fixed mapping diagnostic slice; executable-map denial unqualified")
        return 0
    except Exception:
        print(failure_summary(allocated, cleanup_started))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
