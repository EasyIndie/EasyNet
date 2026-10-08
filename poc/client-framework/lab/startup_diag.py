"""Fixed startup diagnostic; importing performs no fixture or native I/O."""
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


def healthy(result, expected):
    """Lifecycle success alone is insufficient: rc and exact bytes also matter."""
    flags = ("reaped", "waitid_exit_observed", "leader_wait_completed",
             "helper_wait_completed", "stdout_eof", "stderr_eof",
             "stdout_closed", "stderr_closed")
    return (all(result[name] is True for name in flags)
            and result["timed_out"] is False and result["returncode"] == 0
            and 0 <= result["elapsed_s"] < 1
            and result["group_check"] == "sole-zombie"
            and result["primary_class"] == result["cleanup_class"] == "none"
            and result["primary_errno"] is None and result["cleanup_errno"] is None
            and result["errors"] == [] and result["signals"] == []
            and result["stdout"] == expected and result["stderr"] == b""
            and result["stdout_count"] == len(expected) <= 8192
            and result["stderr_count"] == 0)


def sequence(control, operation, expected, end, clock, emit):
    """Injectable fixed A/B/C sequence; failures stop before the next callback."""
    for label in ("A", "B", "C"):
        try:
            budget = min(2, end - clock() - 0.3)
            require(budget > 0.35, "startup budget exhausted")
            result = operation(budget) if label == "C" else control(label == "B", budget)
            wanted = expected if label == "C" else b""
            passed = healthy(result, wanted) and result["elapsed_s"] <= budget and clock() < end
            record = {name: result[name] for name in FIELDS}
            record.update(case=label, expected_match=result["stdout"] == wanted,
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
    end = time.monotonic() + 10
    allocated = cleanup_started = False
    if sys.argv[1:] or sys.platform != "darwin" or os.getuid() == 0:
        print('FAIL/unknown: exact no-argument unprivileged Darwin driver required')
        return 1
    try:
        path = Path(__file__).absolute().parent / "isolate.py"
        spec = importlib.util.spec_from_file_location("startup_isolate", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        require(time.monotonic() < end, "setup deadline exhausted")
        root = Path(tempfile.mkdtemp(prefix="easynet-g0-06-isolate-", dir="/private/tmp"))
        allocated = True
        require(time.monotonic() < end, "setup deadline exhausted")
        os.chmod(root, 0o700)
        allowed_nonce = None
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
            if name == "allowed":
                allowed_nonce = nonce
        allowed = root / "allowed"
        require(time.monotonic() < end, "setup deadline exhausted")
        module.freeze_fixture(allowed)
        profile = path.parent / "fixture.sb"
        passed = sequence(
            lambda sandboxed, budget: module.run_startup_control(profile, allowed, sandboxed, budget),
            lambda budget: module.run_probe(profile, allowed, ["/bin/cat", str(allowed / "seed")], budget),
            allowed_nonce, end, time.monotonic,
            lambda record: print(json.dumps(record, sort_keys=True)))
        require(passed, "startup outcome unqualified")
        cleanup_started = True
        clean_fixture(module, allowed, end)
        print("PASS: fixed startup diagnostic slice")
        return 0
    except Exception:
        print(failure_summary(allocated, cleanup_started))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
