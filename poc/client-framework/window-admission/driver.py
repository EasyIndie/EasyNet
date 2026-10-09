#!/usr/bin/env python3
"""Source-only proposal. An independently frozen runtime binding is mandatory."""
import argparse
import hashlib
import json
import os
import platform
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


class Refusal(Exception):
    pass


class CleanupUnproven(Refusal):
    pass


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
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        signal.signal(signal.SIGTERM, lambda *_: cancelled.__setitem__(0, True))
        ready_r, ready_w = pipe()
        leader = os.fork()
        if leader == 0:
            try:
                close_except({ready_w})
                os.setpgid(0, 0)
                signal.signal(signal.SIGTERM, signal.SIG_DFL)
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
        close(ready_r)
        if not group_ready or reason != "complete" or cancelled[0]:
            raise Refusal("guardian-start")
        stdout_r, stdout_w = pipe(); stderr_r, stderr_w = pipe()
        exec_r, exec_w = pipe()  # Python pipe descriptors are non-inheritable across exec.
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
                reason = "startup-timeout"; break
            drain(0.01)
            if reason != "complete": break
            waited, status = os.waitpid(child, os.WNOHANG)
            if waited == child:
                child_code = os.waitstatus_to_exitcode(status); child_reaped = True; break
        else:
            reason = "timeout"
    except BaseException:
        if reason == "complete": reason = "guardian-refused"
    finally:
        try:
            if group_ready:
                signal_owned(os.killpg, leader, signal.SIGTERM)
            if child is not None and not child_reaped:
                signal_owned(os.kill, child, signal.SIGTERM)  # Pre-setpgid setup too.
            end = min(deadline - 0.5, time.monotonic() + 0.1)
            while time.monotonic() < end: drain(0.005)
            if group_ready: signal_owned(os.killpg, leader, signal.SIGKILL)
            if child is not None and not child_reaped:
                signal_owned(os.kill, child, signal.SIGKILL)
                child_code = reap_before(child, deadline - 0.15); child_reaped = True
            if leader is not None:
                if not group_ready: signal_owned(os.kill, leader, signal.SIGKILL)
                reap_before(leader, deadline - 0.1)
            direct_reaped = leader is not None and (child is None or child_reaped)
            if group_ready:
                try: os.killpg(leader, 0)  # Read-only after reap; never signal again.
                except ProcessLookupError: reclaimed = True
            else:
                reclaimed = child is None
            while reader is not None and reader.get_map() and time.monotonic() < deadline - 0.05:
                drain(0.005)
                if not any(key.data != "control" for key in reader.get_map().values()): break
            if reader is not None and any(key.data != "control" for key in reader.get_map().values()):
                reason = "drain-unproven"
        except BaseException:
            reason = "cleanup-unproven"
        if reader is not None: reader.close()
        for fd in list(owned_fds - {result}):
            try: close(fd)
            except OSError: reason = "fd-close-unproven"
        record = {"reason": reason, "code": child_code, "exec_ready": exec_ready,
                  "direct_reaped": direct_reaped, "group_absent": reclaimed,
                  "fds_closed": owned_fds == {result},
                  "stdout": streams["stdout"].decode("utf-8", errors="replace"),
                  "stderr": streams["stderr"].decode("utf-8", errors="replace")}
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
    except BaseException:
        raise CleanupUnproven("guardian-interrupted") from None
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
                raise CleanupUnproven("guardian-reap-unproven")
            time.sleep(0.01)
    try:
        record = json.loads(payload)
        if not (record["direct_reaped"] and record["group_absent"] and record["fds_closed"]):
            raise CleanupUnproven("group-cleanup-unproven")
    except (ValueError, KeyError, TypeError):
        raise CleanupUnproven("guardian-record-unproven") from None
    if record["reason"] != "complete" or record["code"] != 0 or not (
            record["direct_reaped"] and record["group_absent"]):
        raise Refusal("child-refused")
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


def cleanup(owned, deadline):
    # Directory-relative no-follow handles anchor all validation and removal.
    owned.verify()
    held = []
    entries = []
    count = 0

    def check_budget():
        if time.monotonic() >= deadline:
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
    parser.add_argument("--phase", choices=["admit"], required=True)
    args = parser.parse_args()
    try:
        checkout = Path(__file__).absolute().parents[3]
        value = binding(args.binding, checkout)
        parent = checked_path(os.environ.get("RUNNER_TEMP", ""), "dir")
        if parent.stat().st_uid != os.getuid():
            raise Refusal("temp-owner")
        report = admit(value, checkout, parent)
    except (Refusal, OSError, ValueError, KeyError, TypeError):
        report = {"schema": 1, "result": "refused"}
    print(json.dumps(report, separators=(",", ":")))
    return 0 if report["result"] == "admitted" else 1


if __name__ == "__main__":
    sys.exit(main())
