#!/usr/bin/env python3
"""Source-only proposal. An independently frozen runtime binding is mandatory."""
import argparse
import hashlib
import json
import math
import os
import platform
import plistlib
import select
import selectors
import signal
import stat
import sys
import tempfile
import time
from pathlib import Path

SOURCES = (
    "poc/client-framework/window-admission/Host.swift",
    "poc/client-framework/window-admission/driver.py",
    ".github/workflows/client-window-admission.yml",
    "tests/client_framework/WindowAdmissionTests.swift",
    "tests/client_framework/test_window_admission_driver.py",
)
MANIFEST = ["Host.swift", "tmp", "cache", "cache/swift", "cache/clang", "build", "build/Host"]
EFFECTS = ["toolchildren-group-inheritance", "non-daemon-toolchildren", "implicit-signing",
           "guest-framework-writes", "compiler-flags", "guardian-direct-reap-group-reclaim"]
LIMIT = 16384
IDENTITY_PYTHON = "/opt/homebrew/Cellar/python@3.14/3.14.7/Frameworks/Python.framework/Versions/3.14/bin/python3.14"
IDENTITY_PROFILE = {"image_os": "macos15", "image_version": "20260907.0337.1",
    "os_build": "24G830", "architecture": "arm64", "python_version": "3.14.7",
    "python_sha256": "d8f1d508de5acfd500f20d1949528375ff4a1f470efb267f00d1770941cdeee3",
    "provenance": "conditional-official-macos-15-arm64-image", "runner_selector": "macos-15"}
IDENTITY_DEVELOPER = "/Applications/Xcode_16.4.app/Contents/Developer"
IDENTITY_FILES = {
    "os": ("/System/Library/CoreServices/SystemVersion.plist", "plist", ("ProductVersion", "ProductBuildVersion")),
    "xcode": ("/Applications/Xcode_16.4.app/Contents/Info.plist", "plist", ("CFBundleShortVersionString", "CFBundleVersion")),
    "xcode_build": ("/Applications/Xcode_16.4.app/Contents/version.plist", "plist", ("ProductBuildVersion",)),
    "sdk": (IDENTITY_DEVELOPER + "/Platforms/MacOSX.platform/Developer/SDKs/MacOSX15.5.sdk/SDKSettings.json", "json", ("Version", "CanonicalName")),
    "swift": (IDENTITY_DEVELOPER + "/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift", "hash", ())}
IDENTITY_ENUMS = {
    "stage": {"bootstrap-module", "bootstrap", "loader", "source-import", "binding", "image", "source", "reader", "cleanup"},
    "reason": {"module", "deadline", "file", "binding", "identity", "hash", "field", "schema", "cleanup", "reader", "other"},
    "label": {"bootstrap", "python", "driver", "binding", "source", "os", "xcode", "xcode_build", "sdk", "swift", "root"},
    "error": {"none", "permission", "not-found", "interrupted", "os", "other"}}
IDENTITY_CONTEXT = {"stage": "binding", "reason": "binding", "label": "binding"}


def validate_identity_refusal(value):
    if type(value) is not dict or set(value) != {"schema", "result", "stage", "reason", "label", "error", "cleanup"} or (
            type(value["schema"]) is not int or value["schema"] != 1 or value["result"] != "refused"):
        raise ValueError("identity-refusal-schema")
    if any(type(value[key]) is not str or value[key] not in choices for key, choices in IDENTITY_ENUMS.items()):
        raise ValueError("identity-refusal-enum")
    proof = value["cleanup"]
    if type(proof) is not dict or type(proof.get("state")) is not str or proof["state"] not in {"unknown", "observed"}:
        raise ValueError("identity-refusal-proof")
    keys = {"state"} if proof["state"] == "unknown" else {"state", "guardian_proven", "manifest_removed", "fds_closed"}
    if set(proof) != keys or any(type(proof[key]) is not bool for key in keys - {"state"}):
        raise ValueError("identity-refusal-proof")
    if len(json.dumps(value).encode()) > 4096: raise ValueError("identity-refusal-size")
    return value


def identity_refusal(error, cleanup=None):
    context = dict(IDENTITY_CONTEXT)
    if isinstance(error, TimeoutError) or isinstance(error, Refusal) and str(error) == "identity-deadline": context["reason"] = "deadline"
    return validate_identity_refusal(dict(schema=1, result="refused", error=error_category(error),
        cleanup=cleanup or {"state": "unknown"}, **context))


def identity_deadline(value):
    if type(value) not in {float, int} or not math.isfinite(value) or not 5 < value - identity_clock() <= 90:
        raise Refusal("identity-deadline")
    return value


def identity_tick(deadline):
    if deadline is not None and identity_clock() >= deadline: raise Refusal("identity-deadline")


def identity_clock():
    return time.clock_gettime(time.CLOCK_MONOTONIC)


def read_fixed(path, limit, deadline=None):
    """Walk retained no-follow directory FDs and read one stable regular file."""
    fds, data = [], bytearray()
    closure = CleanupAttempts()
    try:
        parts = Path(path).parts
        if parts[0] != "/" or ".." in parts: raise Refusal("metadata-path")
        fds.append(os.open("/", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW))
        for index, name in enumerate(parts[1:]):
            identity_tick(deadline)
            final = index == len(parts) - 2
            before = os.stat(name, dir_fd=fds[-1], follow_symlinks=False)
            if final and not stat.S_ISREG(before.st_mode): raise Refusal("metadata-owner-type")
            flags = os.O_RDONLY | os.O_NOFOLLOW | (os.O_NONBLOCK if final else os.O_DIRECTORY)
            fd = os.open(name, flags, dir_fd=fds[-1]); fds.append(fd)
            info = os.fstat(fd)
            if identity(info) != identity(before) or info.st_uid not in {0, os.getuid()} or (final and not stat.S_ISREG(info.st_mode)):
                raise Refusal("metadata-owner-type")
        original = os.fstat(fds[-1])
        if original.st_size > limit: raise Refusal("metadata-size")
        hashed = hashlib.sha256()
        count = 0
        while True:
            identity_tick(deadline)
            block = os.read(fds[-1], min(65536, limit - count + 1))
            if not block: break
            count += len(block)
            if count > limit: raise Refusal("metadata-size")
            hashed.update(block)
            if limit <= 1048576: data.extend(block)
        after = os.fstat(fds[-1])
        named = os.stat(parts[-1], dir_fd=fds[-2], follow_symlinks=False)
        stable = lambda info: (identity(info), info.st_size, info.st_mtime_ns, info.st_ctime_ns)
        if stable(original) != stable(after) or stable(named) != stable(after) or count != after.st_size:
            raise Refusal("metadata-drift")
        return bytes(data), hashed.hexdigest(), count
    finally:
        for fd in reversed(fds): closure.attempt("fd-close", lambda fd=fd: os.close(fd))
        if closure.stage is not None:
            IDENTITY_CONTEXT.update(stage="cleanup", reason="cleanup")
            raise Refusal("metadata-fd-close")


def identity_binding(value):
    required = {"schema", "phase", "accepted", "one_guest", "profile", "source_hashes"}
    if not isinstance(value, dict) or set(value) != required or type(value["schema"]) is not int or (
            value["schema"] != 1 or value["phase"] != "identity" or value["accepted"] is not True or
            value["one_guest"] is not True or value["profile"] != IDENTITY_PROFILE):
        raise Refusal("identity-binding")
    hashes = value["source_hashes"]
    if not isinstance(hashes, dict) or set(hashes) != set(SOURCES) or any(
            type(item) is not str or len(item) != 64 or any(c not in "0123456789abcdef" for c in item)
            for item in hashes.values()): raise Refusal("identity-hashes")
    return value


def identity_read(deadline):
    records = {}
    IDENTITY_CONTEXT.update(stage="reader", reason="file", label="python")
    _, python_hash, executable_bytes = read_fixed(IDENTITY_PYTHON, 536870912, deadline - 5)
    if python_hash != IDENTITY_PROFILE["python_sha256"]: raise Refusal("identity-python-hash")
    for label, (path, kind, keys) in IDENTITY_FILES.items():
        IDENTITY_CONTEXT.update(label=label, reason="file")
        raw, hashed, count = read_fixed(path, 536870912 - executable_bytes if kind == "hash" else 1048576, deadline - 5)
        executable_bytes += count if kind == "hash" else 0
        if executable_bytes > 536870912: raise Refusal("metadata-executable-size")
        fields = {}
        if keys:
            IDENTITY_CONTEXT["reason"] = "field"
            value = plistlib.loads(raw) if kind == "plist" else json.loads(raw)
            for key in keys:
                item = value[key]
                if type(item) is not str or not 0 < len(item) <= 64 or item.lower() in {
                        "unknown", "pending", "unfrozen", "unverified"} or any(
                        c not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-" for c in item):
                    raise Refusal("metadata-field")
                fields[key] = item
        records[label] = {"sha256": hashed, "fields": fields}
    if records["os"]["fields"]["ProductBuildVersion"] != IDENTITY_PROFILE["os_build"]:
        raise Refusal("metadata-os-build")
    return {"schema": 1, "result": "identity-observed", "records": records, "swift_cli_version": "unknown"}


def identity_read_report(deadline):
    try: return identity_read(deadline)
    except BaseException as error: return identity_refusal(error)


def identity_observe(value, checkout, parent, overall):
    IDENTITY_CONTEXT.update(stage="image", reason="identity", label="python")
    if platform.system() != "Darwin" or platform.machine() != "arm64" or any(
            os.environ.get(envkey) != value["profile"][key] for envkey, key in (
                ("ImageOS", "image_os"), ("ImageVersion", "image_version"))) or (
            sys.version_info[:3] != (3, 14, 7) or sys.executable != IDENTITY_PYTHON):
        raise Refusal("identity-image-python")
    for source in SOURCES:
        IDENTITY_CONTEXT.update(stage="source", reason="hash", label="source")
        if read_fixed(str(checkout / source), 1048576, overall - 5)[1] != value["source_hashes"][source]:
            raise Refusal("identity-source-hash")
    root = Path(tempfile.mkdtemp(prefix="easynet-identity-", dir=parent)); os.chmod(root, 0o700)
    owned, safe_cleanup, result = OwnedRoot(root), True, None
    proof = {"state": "unknown"}
    try:
        (root / "tmp").mkdir(mode=0o700)
        source = root / "tmp/reader.py"
        raw, _, _ = read_fixed(str(checkout / SOURCES[1]), 1048576, overall - 5); source.write_bytes(raw)
        if digest(source) != value["source_hashes"][SOURCES[1]]: raise Refusal("identity-copy")
        env = {"PATH": "/usr/bin:/bin", "LANG": "C", "TMPDIR": str(root / "tmp")}
        argv = [IDENTITY_PYTHON, "-I", "-B", "-c",
                "import json,runpy,sys;print(json.dumps(runpy.run_path(sys.argv[1])['identity_read_report'](float(sys.argv[2]))))", str(source), str(overall)]
        IDENTITY_CONTEXT.update(stage="reader", reason="reader", label="driver")
        remaining = min(45, overall - identity_clock() - 5)
        if remaining < 2: raise Refusal("identity-deadline")
        raw = bounded(argv, env, root, remaining)
        proof = {"state": "observed", "guardian_proven": True, "manifest_removed": False, "fds_closed": False}
        if len(raw.encode()) > 4096: raise Refusal("identity-report-size")
        result = json.loads(raw)
        if result.get("result") == "refused":
            raise IdentityFailure(validate_identity_refusal(result))
        if set(result) != {"schema", "result", "records", "swift_cli_version"} or (
                type(result["schema"]) is not int or result["schema"] != 1 or result["result"] != "identity-observed" or
                result["swift_cli_version"] != "unknown" or set(result["records"]) != set(IDENTITY_FILES)):
            raise Refusal("identity-report-schema")
        for label, record in result["records"].items():
            if set(record) != {"sha256", "fields"} or type(record["sha256"]) is not str or (
                    len(record["sha256"]) != 64 or any(c not in "0123456789abcdef" for c in record["sha256"])) or (
                    set(record["fields"]) != set(IDENTITY_FILES[label][2]) or any(type(item) is not str or
                    not 0 < len(item) <= 64 or any(c not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
                    for c in item) for item in record["fields"].values())):
                raise Refusal("identity-report-fields")
        return result
    except CleanupUnproven:
        safe_cleanup = False
        raise
    except BaseException as error:
        report = error.report if isinstance(error, IdentityFailure) else identity_refusal(error, proof)
        raise IdentityFailure(report) from None
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)  # Reserved cleanup is governed by the hard deadline.
        signal.setitimer(signal.ITIMER_REAL, max(0.001, overall - identity_clock()))
        IDENTITY_CONTEXT.update(stage="cleanup", reason="cleanup", label="root")
        try:
            if safe_cleanup:
                cleanup(owned, overall, clock=identity_clock)
                if proof["state"] == "observed": proof["manifest_removed"] = True
        except BaseException as error:
            raise IdentityFailure(identity_refusal(error, proof)) from None
        finally:
            closed = CleanupAttempts()
            for name in ("fd", "parent"):
                fd = getattr(owned, name)
                if fd is not None: closed.attempt("fd-close", lambda fd=fd: os.close(fd))
            if closed.stage is not None: raise IdentityFailure(identity_refusal(Refusal("identity-root-fd-close"), proof))
            if proof["state"] == "observed": proof["fds_closed"] = True
            if result is not None:
                result["cleanup"] = proof
                if len(json.dumps(result).encode()) > 4096: raise Refusal("identity-report-size")


class Refusal(Exception):
    def __init__(self, reason, evidence=None):
        self.evidence = validate_evidence(evidence) if evidence is not None else None
        super().__init__(json.dumps(self.evidence, separators=(",", ":")) if self.evidence else reason)


class CleanupUnproven(Refusal):
    pass


class IdentityFailure(Refusal):
    def __init__(self, report):
        self.report = validate_identity_refusal(report)
        super().__init__("identity-refused")

PROOF_FLAGS = {"child_started", "sentinel_started", "child_reaped", "sentinel_reaped",
               "group_absent", "fds_closed", "drain_complete", "exec_ready", "deadline"}
PROOF_ENUMS = {
    "reason": {"complete", "parent-eof", "exec-refused", "overflow", "cancel", "startup-timeout",
               "timeout", "guardian-refused", "cleanup-unproven", "drain-unproven",
               "fd-close-unproven", "guardian-interrupted", "guardian-reap-unproven",
               "guardian-record-unproven", "guardian-output", "guardian-deadline"},
    "cleanup_stage": {"env", "start", "sentinel", "child", "term", "drain", "kill",
                      "reap-child", "reap-sentinel", "group-check", "fd-close", "done", "group-kill", "direct-kill"},
    "error": {"none", "permission", "not-found", "interrupted", "os", "other"},
    "exit": {"zero", "nonzero", "signal", "unknown", "not-started"}}


def validate_evidence(value):
    if not isinstance(value, dict) or set(value) != PROOF_FLAGS | set(PROOF_ENUMS) | {"schema"}:
        raise ValueError("evidence-schema")
    if type(value["schema"]) is not int or value["schema"] != 1 or any(
            type(value[key]) is not bool for key in PROOF_FLAGS):
        raise ValueError("evidence-type")
    if any(type(value[key]) is not str or value[key] not in allowed for key, allowed in PROOF_ENUMS.items()):
        raise ValueError("evidence-enum")
    if len(json.dumps(value, separators=(",", ":")).encode()) > 1024:
        raise ValueError("evidence-size")
    return value


def unknown_evidence(reason, expired=False):
    return dict(schema=1, reason=reason, cleanup_stage="start", error="none", exit="unknown",
                **{key: expired if key == "deadline" else False for key in PROOF_FLAGS})


def cleanup_proven(proof):
    return proof["reason"] not in {"cleanup-unproven", "drain-unproven", "fd-close-unproven"} and all(not proof[started] or proof[reaped] for started, reaped in (
        ("child_started", "child_reaped"), ("sentinel_started", "sentinel_reaped"))) and all(
        proof[key] for key in ("group_absent", "fds_closed", "drain_complete"))


def error_category(error):
    return ("permission" if isinstance(error, PermissionError) else "not-found" if isinstance(
        error, FileNotFoundError) else "interrupted" if isinstance(error, InterruptedError) else
        "os" if isinstance(error, OSError) else "other")


def checked_path(value, kind):
    path = Path(value)
    if not path.is_absolute() or ".." in path.parts:
        raise Refusal("unsafe-path")
    for component in [*reversed(path.parents), path]:
        info = component.lstat()
        if stat.S_ISLNK(info.st_mode):
            raise Refusal("unsafe-path")
    info = path.stat()
    if (kind == "file" and not stat.S_ISREG(info.st_mode)) or (
            kind == "dir" and not stat.S_ISDIR(info.st_mode)):
        raise Refusal("unsafe-path")
    return path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def binding(path, checkout):
    raw = checked_path(path, "file").read_bytes()
    if len(raw) > 16384:
        raise Refusal("binding-size")
    value = json.loads(raw)
    required = {"schema", "accepted", "source_hashes", "image_os", "image_version",
        "os_build", "architecture", "runner_selector", "developer", "compiler", "sdk",
                "xcode_version", "swift_version", "compiler_hash", "xcodebuild_hash",
                "sdk_settings_hash", "provenance", "effects", "manifest", "one_guest"}
    if not isinstance(value, dict) or set(value) != required:
        raise Refusal("binding-incomplete")
    if value["schema"] != 1 or value["accepted"] is not True or value["one_guest"] is not True:
        raise Refusal("binding-unaccepted")
    if value["effects"] != {key: True for key in EFFECTS} or value["manifest"] != MANIFEST:
        raise Refusal("effects-unaccepted")
    for key in required - {"schema", "accepted", "source_hashes", "effects", "manifest", "one_guest"}:
        if not isinstance(value[key], str) or not value[key].strip() or value[key].lower() in {
                "unknown", "pending", "unfrozen", "unverified"}:
            raise Refusal("binding-unknown")
    if value["architecture"] != "arm64" or value["runner_selector"] != "macos-15" or value["provenance"] != "reviewed-installed-vendor-toolchain":
        raise Refusal("toolchain-unaccepted")
    hashes = value["source_hashes"]
    if not isinstance(hashes, dict) or set(hashes) != set(SOURCES):
        raise Refusal("source-identity")
    for source in SOURCES:
        if hashes[source] != digest(checked_path(str(checkout / source), "file")):
            raise Refusal("source-identity")
    return value


def clean_environment(env):
    if set(env) - {"PATH", "LANG", "TMPDIR", "DEVELOPER_DIR"} or any(
            not isinstance(value, str) for value in env.values()):
        raise Refusal("child-environment")
    if env.get("PATH") != "/usr/bin:/bin" or env.get("LANG") != "C" or "TMPDIR" not in env:
        raise Refusal("child-environment")
    os.environ.clear()
    os.environ.update(env)


def close_except(keep):
    # os.closerange is public; no private Popen state or platform-specific spawn assumption.
    maximum = os.sysconf("SC_OPEN_MAX")
    if not isinstance(maximum, int) or maximum < 3:
        raise Refusal("fd-bound-unknown")
    start = 3
    for fd in sorted(fd for fd in keep if fd >= 3):
        os.closerange(start, fd)
        start = fd + 1
    os.closerange(start, maximum)


def reap_before(pid, deadline):
    while time.monotonic() < deadline:
        try:
            waited, status = os.waitpid(pid, os.WNOHANG)
        except InterruptedError:
            continue
        if waited == pid:
            return os.waitstatus_to_exitcode(status)
        time.sleep(0.005)
    raise CleanupUnproven("direct-reap-deadline")


def signal_owned(function, pid, sig):
    try: function(pid, sig)
    except ProcessLookupError: pass  # Already empty/exited; mandatory reaps follow.


class CleanupAttempts:
    """Run every owned cleanup action; retain the first failure independently."""
    def __init__(self):
        self.stage, self.error, self.expired = None, "none", False

    def fail(self, stage, error=None):
        if self.stage is None:
            self.stage, self.error = stage, error_category(error) if error is not None else "none"
        self.expired |= isinstance(error, CleanupUnproven)

    def attempt(self, stage, action):
        try:
            action()
        except BaseException as error:
            self.fail(stage, error)


def guardian(argv, env, cwd, budget, control, result):
    """Explicit fork/exec startup: known unreaped PID before any child setup."""
    deadline = time.monotonic() + budget - 0.1
    leader = child = None
    group_ready = False
    child_code = None
    child_reaped = False
    reader = None
    streams = {"stdout": bytearray(), "stderr": bytearray()}
    owned_fds = {control, result}
    reason, reclaimed, direct_reaped, exec_ready = "complete", False, False, False
    cancelled = [False]
    stage, failed_stage, failure = "env", None, "none"
    sentinel_reaped = drain_complete = expired = False
    cleanup_attempts = CleanupAttempts()
    selector_closed = True

    def pipe():
        pair = os.pipe()
        owned_fds.update(pair)
        return pair

    def close(fd):
        os.close(fd)
        owned_fds.remove(fd)

    def drain(wait):
        nonlocal reason, exec_ready
        for key, _ in reader.select(wait):
            data = os.read(key.fd, 4096)
            if key.data == "control":
                if not data:
                    reason = "parent-eof"; reader.unregister(key.fd)
            elif key.data == "startup":
                if data:
                    reason = "exec-refused"
                else:
                    exec_ready = True; reader.unregister(key.fd)
            elif not data:
                reader.unregister(key.fd)
            elif sum(map(len, streams.values())) + len(data) <= LIMIT:
                streams[key.data].extend(data)
            else:
                reason = "overflow"

    try:
        clean_environment(env)  # Before sentinel/compiler forks; no inherited credentials.
        close_except(owned_fds)  # Discard driver's retained directory descriptors in guardian.
        reader = selectors.DefaultSelector()
        selector_closed = False
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        signal.signal(signal.SIGTERM, lambda *_: cancelled.__setitem__(0, True))
        stage = "sentinel"
        ready_r, ready_w = pipe()
        leader = os.fork()
        if leader == 0:
            try:
                close_except({ready_w})
                os.setpgid(0, 0)
                signal.signal(signal.SIGTERM, signal.SIG_IGN)
                os.write(ready_w, b"R"); os.close(ready_w)
                while True: signal.pause()
            finally:
                os._exit(1)
        close(ready_w)
        reader.register(control, selectors.EVENT_READ, "control")
        # This handshake has its own finite startup budget and EOF/cancel observation.
        startup = min(deadline - 1, time.monotonic() + 0.5)
        while time.monotonic() < startup and not cancelled[0]:
            if select.select([ready_r], [], [], 0.01)[0]:
                group_ready = os.read(ready_r, 1) == b"R"; break
            drain(0)
            if reason != "complete": break
        expired |= not group_ready and time.monotonic() >= startup
        close(ready_r)
        if not group_ready or reason != "complete" or cancelled[0]:
            raise Refusal("guardian-start")
        stdout_r, stdout_w = pipe(); stderr_r, stderr_w = pipe()
        exec_r, exec_w = pipe()  # Python pipe descriptors are non-inheritable across exec.
        stage = "child"
        child = os.fork()
        if child == 0:
            try:
                os.setpgid(0, leader)
                os.chdir(cwd)
                null = os.open("/dev/null", os.O_RDONLY)
                os.dup2(null, 0); os.dup2(stdout_w, 1); os.dup2(stderr_w, 2)
                close_except({exec_w})
                signal.signal(signal.SIGTERM, signal.SIG_DFL)
                signal.signal(signal.SIGINT, signal.SIG_DFL)
                os.execve(argv[0], argv, env)
            except BaseException:
                try: os.write(exec_w, b"F")
                except OSError: pass
            os._exit(127)
        for fd in (stdout_w, stderr_w, exec_w): close(fd)
        for fd, name in ((stdout_r, "stdout"), (stderr_r, "stderr"), (exec_r, "startup")):
            os.set_blocking(fd, False); reader.register(fd, selectors.EVENT_READ, name)
        startup = min(deadline - 1, time.monotonic() + 0.5)
        while time.monotonic() < deadline - 1:
            if cancelled[0]: reason = "cancel"; break
            if not exec_ready and time.monotonic() >= startup:
                expired = True; reason = "startup-timeout"; break
            drain(0.01)
            if reason != "complete": break
            waited, status = os.waitpid(child, os.WNOHANG)
            if waited == child:
                child_code = os.waitstatus_to_exitcode(status); child_reaped = True; break
        else:
            expired = True; reason = "timeout"
    except BaseException as error:
        failed_stage, failure = stage, error_category(error)
        if reason == "complete": reason = "guardian-refused"
    finally:
        operation_reason = reason
        def grace_drain():
            end = min(deadline - 0.5, time.monotonic() + 0.1)
            while reader is not None and time.monotonic() < end: drain(0.005)

        def reap_child():
            nonlocal child_code, child_reaped
            child_code = reap_before(child, deadline - 0.15); child_reaped = True

        def reap_sentinel():
            nonlocal sentinel_reaped
            reap_before(leader, deadline - 0.1); sentinel_reaped = True

        def group_check():
            nonlocal reclaimed
            if group_ready:
                try: os.killpg(leader, 0)  # Read-only after reap; never signal again.
                except ProcessLookupError: reclaimed = True
            else:
                reclaimed = child is None and (leader is None or sentinel_reaped)
            if not reclaimed: cleanup_attempts.fail("group-check")

        def final_drain():
            nonlocal expired, drain_complete
            while reader is not None and reader.get_map() and time.monotonic() < deadline - 0.05:
                drain(0.005)
                if not any(key.data != "control" for key in reader.get_map().values()): break
            if reader is not None and any(key.data != "control" for key in reader.get_map().values()):
                expired |= time.monotonic() >= deadline - 0.05
                cleanup_attempts.fail("drain")
            else: drain_complete = True

        def close_selector():
            nonlocal selector_closed
            reader.close(); selector_closed = True

        # Signals and closes are attempted even after deadlines; only waits are bounded.
        if group_ready:
            cleanup_attempts.attempt("term", lambda: signal_owned(os.killpg, leader, signal.SIGTERM))
        if child is not None and not child_reaped:
            cleanup_attempts.attempt("term", lambda: signal_owned(os.kill, child, signal.SIGTERM))
        cleanup_attempts.attempt("drain", grace_drain)
        if group_ready:  # Sentinel is still held, unreaped, through this group operation.
            cleanup_attempts.attempt("group-kill", lambda: signal_owned(os.killpg, leader, signal.SIGKILL))
        if child is not None and not child_reaped:
            cleanup_attempts.attempt("direct-kill", lambda: signal_owned(os.kill, child, signal.SIGKILL))
            cleanup_attempts.attempt("reap-child", reap_child)
        if leader is not None and not sentinel_reaped:
            cleanup_attempts.attempt("kill", lambda: signal_owned(os.kill, leader, signal.SIGKILL))
            cleanup_attempts.attempt("reap-sentinel", reap_sentinel)
        direct_reaped = sentinel_reaped and (child is None or child_reaped)
        cleanup_attempts.attempt("group-check", group_check)
        cleanup_attempts.attempt("drain", final_drain)
        if reader is not None: cleanup_attempts.attempt("fd-close", close_selector)
        for fd in list(owned_fds - {result}):
            cleanup_attempts.attempt("fd-close", lambda fd=fd: close(fd))
        expired |= cleanup_attempts.expired
        if cleanup_attempts.stage is not None:
            failed_stage, failure = cleanup_attempts.stage, cleanup_attempts.error
            reason = "cleanup-unproven"  # Later fallback success cannot clear a failed attempt.
        elif operation_reason != "complete":
            reason = operation_reason
        fds_closed = selector_closed and owned_fds == {result}
        record = {"reason": reason, "code": child_code, "exec_ready": exec_ready,
                  "direct_reaped": direct_reaped, "group_absent": reclaimed,
                  "fds_closed": fds_closed,
                  "stdout": streams["stdout"].decode("utf-8", errors="replace"),
                  "stderr": streams["stderr"].decode("utf-8", errors="replace")}
        record["evidence"] = validate_evidence(dict(schema=1, reason=reason,
            cleanup_stage=failed_stage or "done", error=failure, child_started=child is not None,
            sentinel_started=leader is not None, child_reaped=child_reaped, sentinel_reaped=sentinel_reaped,
            group_absent=reclaimed, fds_closed=fds_closed, drain_complete=drain_complete,
            exec_ready=exec_ready, deadline=expired, exit="not-started" if child is None else
            "unknown" if child_code is None else "zero" if child_code == 0 else "signal" if child_code < 0 else "nonzero"))
        payload = json.dumps(record).encode()
        os.set_blocking(result, False)
        try:
            while payload and time.monotonic() < deadline:
                if select.select([], [result], [], 0.005)[1]:
                    payload = payload[os.write(result, payload):]
        except OSError: pass
        os.close(result)
        os._exit(0)


def bounded(argv, env, cwd, budget):
    clean_environment(env)  # Driver also sanitizes before the first guardian fork.
    control_r, control_w = os.pipe()
    try:
        result_r, result_w = os.pipe()
    except BaseException:
        os.close(control_r); os.close(control_w)
        raise
    try:
        pid = os.fork()
    except BaseException:
        for fd in (control_r, control_w, result_r, result_w): os.close(fd)
        raise
    if pid == 0:
        os.close(control_w); os.close(result_r)
        guardian(argv, env, cwd, budget, control_r, result_w)
    os.close(control_r); os.close(result_w)
    payload = bytearray()
    deadline = time.monotonic() + budget
    try:
        while time.monotonic() < deadline:
            if select.select([result_r], [], [], 0.05)[0]:
                block = os.read(result_r, 4096)
                if not block:
                    break
                payload.extend(block)
                if len(payload) > 49152:
                    raise Refusal("guardian-output")
        else:
            raise Refusal("guardian-deadline")
    except BaseException as error:
        reason = str(error) if isinstance(error, Refusal) and str(error) in {
            "guardian-output", "guardian-deadline"} else "guardian-interrupted"
        raise CleanupUnproven(reason, unknown_evidence(reason, reason == "guardian-deadline")) from None
    finally:
        os.close(control_w)  # EOF requests cleanup even on cancel / reader failure.
        os.close(result_r)
        # Guardian owns cleanup; do not kill it and abandon its children.
        while True:
            try:
                waited, _ = os.waitpid(pid, os.WNOHANG)
            except InterruptedError:
                continue
            if waited == pid:
                break
            if time.monotonic() > deadline:
                raise CleanupUnproven("guardian-reap-unproven", unknown_evidence("guardian-reap-unproven", True))
            time.sleep(0.01)
    try:
        record = json.loads(payload)
        proof = validate_evidence(record["evidence"])
        if not cleanup_proven(proof):
            raise CleanupUnproven("group-cleanup-unproven", proof)
    except (ValueError, KeyError, TypeError):
        raise CleanupUnproven("guardian-record-unproven", unknown_evidence("guardian-record-unproven")) from None
    if proof["reason"] != "complete" or proof["exit"] != "zero" or proof["deadline"] or not all(
            proof[key] for key in ("child_started", "sentinel_started", "exec_ready")):
        raise Refusal("child-refused", proof)
    return record["stdout"].strip()


def identity(info):
    return info.st_dev, info.st_ino, info.st_mode, info.st_uid


class OwnedRoot:
    def __init__(self, path):
        self.path = Path(path)
        self.parent = self.fd = None
        try:
            flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
            self.parent = os.open(checked_path(str(self.path.parent), "dir"), flags)
            self.fd = os.open(self.path.name, flags, dir_fd=self.parent)
            self.original = identity(os.fstat(self.fd))
            self.verify()
        except BaseException:
            self.close()
            raise

    def verify(self):
        current = os.stat(self.path.name, dir_fd=self.parent, follow_symlinks=False)
        if identity(current) != self.original or identity(os.fstat(self.fd)) != self.original or (
                current.st_uid != os.getuid() or not stat.S_ISDIR(current.st_mode) or
                stat.S_IMODE(current.st_mode) != 0o700):
            raise Refusal("root-identity")

    def close(self):
        for name in ("fd", "parent"):
            value = getattr(self, name)
            if value is not None:
                os.close(value); setattr(self, name, None)


def cleanup(owned, deadline, clock=time.monotonic):
    # Directory-relative no-follow handles anchor all validation and removal.
    owned.verify()
    held = []
    entries = []
    count = 0

    def check_budget():
        if clock() >= deadline:
            raise Refusal("filesystem-cleanup-deadline")

    def visit(fd, prefix, depth):
        nonlocal count
        check_budget()
        if depth > 32:
            raise Refusal("manifest-depth")
        with os.scandir(fd) as listing:
            names = []
            for entry in listing:
                check_budget()
                count += 1
                if count > 4096: raise Refusal("manifest-count")
                names.append(entry.name)
        for name in names:
            check_budget()
            relative = prefix + name
            info = os.stat(name, dir_fd=fd, follow_symlinks=False)
            allowed = relative in MANIFEST or relative.startswith(("tmp/", "cache/swift/", "cache/clang/"))
            if not allowed or info.st_uid != os.getuid() or not (
                    stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode)):
                raise Refusal("manifest-cleanup")
            if stat.S_ISDIR(info.st_mode):
                child = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
                held.append(child)
                if identity(os.fstat(child)) != identity(info): raise Refusal("directory-identity")
                visit(child, relative + "/", depth + 1)
            entries.append((fd, name, identity(info), stat.S_ISDIR(info.st_mode)))

    try:
        visit(owned.fd, "", 0)  # Complete validation before the first removal.
        for fd, name, original, directory in entries:
            check_budget(); owned.verify()
            if identity(os.stat(name, dir_fd=fd, follow_symlinks=False)) != original:
                raise Refusal("entry-identity")
            if directory: os.rmdir(name, dir_fd=fd)
            else: os.unlink(name, dir_fd=fd)
        check_budget(); owned.verify()
        os.rmdir(owned.path.name, dir_fd=owned.parent)
    finally:
        for fd in held: os.close(fd)


def admit(value, checkout, parent):
    if platform.system() != "Darwin" or platform.machine() != "arm64" or (
            os.environ.get("ImageOS") != value["image_os"] or
            os.environ.get("ImageVersion") != value["image_version"]):
        raise Refusal("image-identity")
    developer = checked_path(value["developer"], "dir")
    compiler = checked_path(value["compiler"], "file")
    sdk = checked_path(value["sdk"], "dir")
    xcode = checked_path(str(developer / "usr/bin/xcodebuild"), "file")
    if not str(compiler).startswith(str(developer) + "/") or not str(sdk).startswith(str(developer) + "/"):
        raise Refusal("toolchain-path")
    for path, key in ((compiler, "compiler_hash"), (xcode, "xcodebuild_hash"),
                      (checked_path(str(sdk / "SDKSettings.json"), "file"), "sdk_settings_hash")):
        if digest(path) != value[key]:
            raise Refusal("toolchain-identity")
    root = Path(tempfile.mkdtemp(prefix="easynet-window-", dir=parent))
    os.chmod(root, 0o700)
    owned = OwnedRoot(root)
    safe_cleanup = True
    overall = time.monotonic() + 180
    result = None
    def run(argv, budget):
        remaining = min(budget, overall - time.monotonic() - 5)
        if remaining < 2: raise Refusal("overall-deadline")
        return bounded(argv, env, root, remaining)
    try:
        for entry in ("tmp", "cache", "cache/swift", "cache/clang", "build"):
            (root / entry).mkdir(mode=0o700)
        (root / "Host.swift").write_bytes((checkout / SOURCES[0]).read_bytes())
        if digest(root / "Host.swift") != value["source_hashes"][SOURCES[0]]:
            raise Refusal("source-identity")
        env = {"PATH": "/usr/bin:/bin", "LANG": "C", "TMPDIR": str(root / "tmp"),
               "DEVELOPER_DIR": str(developer)}
        if run(["/usr/bin/sw_vers", "-buildVersion"], 8) != value["os_build"]:
            raise Refusal("os-identity")
        if run([str(xcode), "-version"], 8) != value["xcode_version"] or (
                run([str(compiler), "--version"], 8) != value["swift_version"] or
                run(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path"], 8) != str(sdk)):
            raise Refusal("toolchain-version")
        argv = [str(compiler), "-parse-as-library", "-sdk", str(sdk), "-target", "arm64-apple-macosx15.0",
                "-module-cache-path", str(root / "cache/swift"), "-Xcc",
                "-fmodules-cache-path=" + str(root / "cache/clang"), "-o",
                str(root / "build/Host"), str(root / "Host.swift")]
        run(argv, 120)
        raw = run([str(root / "build/Host"), "--admit"], 15)
        if len(raw.encode()) > 4096:
            raise Refusal("host-report-size")
        report = json.loads(raw)
        if set(report) != {"schema", "result", "visible", "events", "actions", "state_text", "negative", "render_hashes"}:
            raise Refusal("host-schema")
        hashes = report["render_hashes"]
        if report["schema"] != 1 or report["result"] != "admitted" or any(
                report[key] is not True for key in ("visible", "events", "actions", "state_text", "negative")):
            raise Refusal("host-refused")
        if not isinstance(hashes, list) or len(hashes) != 3 or any(
                not isinstance(item, str) or len(item) != 64 or any(c not in "0123456789abcdef" for c in item) for item in hashes) or (
                hashes[0] == hashes[1] or hashes[0] != hashes[2]):
            raise Refusal("render-proof")
        result = {"schema": 1, "result": "admitted", "window": report,
                "source_hashes": list(value["source_hashes"].values()), "direct_reaped": True,
                "identity_hashes": [value[key] for key in (
                    "compiler_hash", "xcodebuild_hash", "sdk_settings_hash")],
                "group_absent": True, "bounded": True, "manifest_cleanup": True}
        return result
    except CleanupUnproven:
        safe_cleanup = False
        raise
    finally:
        try:
            if safe_cleanup:
                cleanup(owned, min(overall, time.monotonic() + 5))
        finally:
            owned.close()
            if result is not None: result["fds_closed"] = True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binding", required=True)
    parser.add_argument("--phase", choices=["admit", "identity"], required=True)
    parser.add_argument("--identity-deadline", type=float)
    args = parser.parse_args()
    try:
        checkout = Path(__file__).absolute().parents[3]
        if args.phase == "identity":
            overall = identity_deadline(args.identity_deadline)
            raw, _, _ = read_fixed(args.binding, 4096, overall - 5)
            value = identity_binding(json.loads(raw))
        else: value = binding(args.binding, checkout)
        parent = checked_path(os.environ.get("RUNNER_TEMP", ""), "dir")
        if parent.stat().st_uid != os.getuid():
            raise Refusal("temp-owner")
        report = identity_observe(value, checkout, parent, overall) if args.phase == "identity" else admit(value, checkout, parent)
    except BaseException as error:
        if args.phase == "identity":
            report = error.report if isinstance(error, IdentityFailure) else identity_refusal(error)
        elif isinstance(error, (Refusal, OSError, ValueError, KeyError, TypeError, plistlib.InvalidFileException)):
            report = {"schema": 1, "result": "refused"}
        else: raise
    finally:
        if args.phase == "identity": signal.setitimer(signal.ITIMER_REAL, 0)
    print(json.dumps(report, separators=(",", ":"), sort_keys=args.phase == "identity"))
    return 0 if report["result"] in {"admitted", "identity-observed"} else 1


if __name__ == "__main__":
    sys.exit(main())
