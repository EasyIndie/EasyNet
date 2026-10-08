"""Darwin synthetic-fixture probes; importing this module performs no I/O."""
import hashlib
import os
from pathlib import Path
import re
import selectors
import signal
import stat
import subprocess
import sys
import time

PROFILE_SHA256 = "b554c29d574b6c1852f7facbdbd8e4fe10af7864ec64637a3191055e2e8e3c82"
CAP = 8192
_fixtures = {}
_live = set()


def _identity(path, directory=False):
    s = path.lstat()
    kind = stat.S_ISDIR if directory else stat.S_ISREG
    if not kind(s.st_mode) or s.st_uid != os.getuid():
        raise ValueError("unowned or nonregular fixture path")
    if stat.S_IMODE(s.st_mode) != (0o700 if directory else 0o600):
        raise ValueError("fixture mode mismatch")
    if not directory and s.st_nlink != 1:
        raise ValueError("hard-linked fixture file")
    return (s.st_dev, s.st_ino, s.st_uid, s.st_mode)


def _root(allowed_root):
    p = Path(allowed_root)
    if not re.fullmatch(r"/private/tmp/easynet-g0-06-isolate-[A-Za-z0-9_-]+/allowed", str(p)):
        raise ValueError("not a canonical fixture root")
    if p.resolve(strict=True) != p:
        raise ValueError("aliased fixture root")
    return p.parent


def freeze_fixture(allowed_root):
    """Register once, before children exist, a complete synthetic manifest."""
    root = _root(allowed_root)
    if str(root) in _fixtures:
        raise ValueError("fixture already frozen")
    entries = {root: _identity(root, True)}
    if {p.name for p in root.iterdir()} != {"allowed", "decoy"}:
        raise ValueError("unexpected root entries")
    hashes = {}
    for name in ("allowed", "decoy"):
        directory = root / name
        entries[directory] = _identity(directory, True)
        if {p.name for p in directory.iterdir()} != {"seed"}:
            raise ValueError("unexpected directory entries")
        seed = directory / "seed"
        entries[seed] = _identity(seed)
        hashes[seed] = hashlib.sha256(seed.read_bytes()).hexdigest()
    _fixtures[str(root)] = (entries, hashes)


def check_fixture(allowed_root):
    root = _root(allowed_root)
    entries, hashes = _fixtures[str(root)]
    for path, identity in entries.items():
        if _identity(path, stat.S_ISDIR(identity[3])) != identity:
            raise ValueError("fixture identity changed")
    for path, digest in hashes.items():
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError("fixture bytes changed")
    for directory in (root, root / "allowed", root / "decoy"):
        expected = {p.name for p in entries if p.parent == directory}
        if {p.name for p in directory.iterdir()} != expected:
            raise ValueError("unexpected fixture names")
    return entries


def note_new(allowed_root):
    """Record only the fixed allowed/new empty output after successful touch."""
    root = _root(allowed_root)
    entries, hashes = _fixtures[str(root)]
    path = root / "allowed/new"
    identity = _identity(path)
    if path in entries or path.read_bytes() != b"":
        raise ValueError("unexpected new file")
    entries[path] = identity
    hashes[path] = hashlib.sha256(b"").hexdigest()
    check_fixture(allowed_root)


def _environment():
    env = {"PATH": "/usr/bin:/bin", "LC_ALL": "C"}
    for name in ("HOME", "CODEX_HOME"):
        if name in os.environ:
            env[name] = os.environ[name]
    return env


def _error_fields(error):
    name = type(error).__name__
    known = {"OSError", "PermissionError", "ProcessLookupError", "FileNotFoundError",
             "InterruptedError", "BlockingIOError", "TimeoutExpired"}
    errno = getattr(error, "errno", None)
    return name if name in known else "other", errno if isinstance(errno, int) else None


def _execute(argv, case, deadline_s=2):
    """Fixed commands; reserve the leader until all group operations finish."""
    start = time.monotonic()
    if not 0 < deadline_s <= 2:
        raise ValueError("invalid deadline")
    end = start + deadline_s
    output = {"stdout": bytearray(), "stderr": bytearray()}
    counts = {"stdout": 0, "stderr": 0}
    eof = {"stdout": False, "stderr": False}
    closed = {"stdout": False, "stderr": False}
    child = selector = None
    timed_out = sent_term = sent_kill = False
    diagnostic = {"phase": "setup", "primary_class": "none", "primary_errno": None,
                  "cleanup_class": "none", "cleanup_errno": None, "errors": [],
                  "waitid_exit_observed": False, "group_check": "unknown",
                  "owned_pid": None, "leader_wait_completed": False,
                  "signals": [], "helper_wait_completed": False}

    def failure(phase, error, cleanup=False):
        kind, errno = _error_fields(error)
        diagnostic["errors"].append({"phase": phase, "class": kind, "errno": errno})
        prefix = "cleanup" if cleanup else "primary"
        if diagnostic[prefix + "_class"] == "none":
            diagnostic[prefix + "_class"], diagnostic[prefix + "_errno"] = kind, errno

    def close_resources(sel, process, phase, flags=None):
        # Each operation is independent: one close error cannot skip another FD.
        for name, resource in (("selector", sel), ("stdout", process.stdout if process else None),
                               ("stderr", process.stderr if process else None)):
            if resource is not None:
                try:
                    resource.close()
                    if flags is not None and name in flags:
                        flags[name] = True
                except Exception as error:
                    failure(phase + "-" + name, error, True)

    def drain(sel, buffers, totals, ended, limit):
        for key, _ in sel.select(max(0, min(0.01, limit - time.monotonic()))):
            data = os.read(key.fileobj.fileno(), 4096)
            name = key.data
            if not data:
                ended[name] = True
                sel.unregister(key.fileobj)
            else:
                totals[name] += len(data)
                buffers[name].extend(data[:max(0, CAP - len(buffers[name]))])

    def observe_group():
        # Internal, exact metadata only. The leader is still reserved by WNOWAIT.
        limit = min(time.monotonic() + 0.15, end - 0.05)
        if limit <= time.monotonic():
            failure("metadata-budget", subprocess.TimeoutExpired("metadata", 0))
            return "unknown"
        helper = sel = None
        data = {"stdout": bytearray(), "stderr": bytearray()}
        total = {"stdout": 0, "stderr": 0}
        ended = {"stdout": False, "stderr": False}
        helper_closed = {"stdout": False, "stderr": False}
        waited = False
        term = kill = expired = False
        before = len(diagnostic["errors"])
        try:
            sel = selectors.DefaultSelector()
            helper = subprocess.Popen(["/bin/ps", "-g", str(child.pid), "-o",
                                       "pid=,ppid=,pgid=,state="],
                                      stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE, env=_environment(), close_fds=True,
                                      start_new_session=True, umask=0o077)
            for name, stream in (("stdout", helper.stdout), ("stderr", helper.stderr)):
                os.set_blocking(stream.fileno(), False)
                sel.register(stream, selectors.EVENT_READ, name)
            while time.monotonic() < limit:
                exited = os.waitid(os.P_PID, helper.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
                now = time.monotonic()
                if not exited and now >= limit - 0.05 and not term:
                    expired = term = True
                    try:
                        os.kill(helper.pid, signal.SIGTERM)
                    except Exception as error:
                        failure("metadata-term", error)
                if not exited and now >= limit - 0.03 and not kill:
                    expired = kill = True
                    try:
                        os.kill(helper.pid, signal.SIGKILL)
                    except Exception as error:
                        failure("metadata-kill", error)
                drain(sel, data, total, ended, limit)
                if exited and all(ended.values()):
                    break
            if expired or not all(ended.values()):
                failure("metadata-timeout", subprocess.TimeoutExpired("metadata", 0.15))
        except Exception as error:
            failure("metadata", error)
        finally:
            if helper is not None:
                # An exceptional read/setup path still owns the helper PID, pre-Wait.
                if not all(ended.values()) and not kill:
                    try:
                        os.kill(helper.pid, signal.SIGKILL)
                    except Exception as error:
                        failure("metadata-cleanup-kill", error, True)
                try:
                    helper.wait(timeout=max(0, limit - time.monotonic()))
                    waited = True
                except Exception as error:
                    failure("metadata-wait", error, True)
            close_resources(sel, helper, "metadata-close", helper_closed)
        diagnostic["helper_wait_completed"] = waited
        if (len(diagnostic["errors"]) != before or not waited or helper.returncode != 0
                or not all(helper_closed.values()) or total["stderr"]
                or total["stdout"] > CAP or not all(ended.values())):
            if len(diagnostic["errors"]) == before:
                failure("metadata-invalid", ValueError("incomplete metadata"))
            return "unknown"
        rows = bytes(data["stdout"]).splitlines()
        parsed = []
        if not 1 <= len(rows) <= 64:
            failure("metadata-rows", ValueError("invalid row count"))
            return "unknown"
        for row in rows:
            match = re.fullmatch(rb"\s*([1-9][0-9]*)\s+([1-9][0-9]*)\s+([1-9][0-9]*)\s+([IRSTUZ][+<>AELNSsVWX]*)\s*", row)
            if not match:
                failure("metadata-parse", ValueError("invalid metadata"))
                return "unknown"
            pid, ppid, pgid = (int(value) for value in match.groups()[:3])
            state = match.group(4)
            if pgid != child.pid or any(item[0] == pid for item in parsed):
                failure("metadata-identity", ValueError("invalid group identity"))
                return "unknown"
            parsed.append((pid, ppid, pgid, state))
        leaders = [row for row in parsed if row[0] == child.pid]
        if (len(leaders) != 1 or leaders[0][1] != os.getpid()
                or not leaders[0][3].startswith(b"Z")):
            failure("metadata-leader", ValueError("leader reservation unproved"))
            return "unknown"
        if len(parsed) == 1:
            return "sole-zombie"
        return "live-members" if any(not row[3].startswith(b"Z") for row in parsed) else "zombie-members"

    def send(sig, phase):
        diagnostic["signals"].append(phase)
        try:
            os.killpg(child.pid, sig)
        except Exception as error:
            failure(phase, error, phase == "cleanup-kill")

    try:
        selector = selectors.DefaultSelector()
        diagnostic["phase"] = "spawn"
        child = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, env=_environment(),
                                 close_fds=True, start_new_session=True, umask=0o077)
        diagnostic["owned_pid"] = child.pid
        _live.add(child.pid)
        for name, stream in (("stdout", child.stdout), ("stderr", child.stderr)):
            os.set_blocking(stream.fileno(), False)
            selector.register(stream, selectors.EVENT_READ, name)
        while time.monotonic() < end:
            diagnostic["phase"] = "waitid"
            exited = os.waitid(os.P_PID, child.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
            diagnostic["waitid_exit_observed"] |= bool(exited)
            if exited and diagnostic["group_check"] != "sole-zombie":
                diagnostic["phase"] = "metadata"
                diagnostic["group_check"] = observe_group()
            now = time.monotonic()
            unresolved = diagnostic["group_check"] != "sole-zombie"
            if unresolved and not sent_term and (now >= end - 0.35 or diagnostic["group_check"] == "live-members"):
                timed_out |= not bool(exited)
                sent_term = True
                send(signal.SIGTERM, "signal-term")
            if unresolved and not sent_kill and now >= end - 0.20:
                sent_kill = True
                send(signal.SIGKILL, "signal-kill")
            diagnostic["phase"] = "drain"
            drain(selector, output, counts, eof, end)
            if any(count > CAP for count in counts.values()) and not any(
                    item["phase"] == "output-overflow" for item in diagnostic["errors"]):
                failure("output-overflow", ValueError("output cap exceeded"))
            if exited and all(eof.values()) and not unresolved:
                break
        else:
            timed_out = True
    except Exception as error:
        failure(diagnostic["phase"], error)
    finally:
        if child is not None:
            # All group operations finish here; the independent Wait cannot be skipped.
            if diagnostic["group_check"] != "sole-zombie" and not sent_kill:
                send(signal.SIGKILL, "cleanup-kill")
            diagnostic["phase"] = "leader-wait"
            try:
                child.wait(timeout=max(0, end - time.monotonic()))
                diagnostic["leader_wait_completed"] = True
            except Exception as error:
                failure("leader-wait", error, True)
        close_resources(selector, child, "close", closed)
    reaped = (child is not None and diagnostic["leader_wait_completed"]
              and diagnostic["waitid_exit_observed"] and diagnostic["group_check"] == "sole-zombie"
              and all(eof.values()) and all(closed.values()) and not diagnostic["errors"] and not timed_out)
    if reaped:
        _live.discard(child.pid)
    return {"case": case, "returncode": child.returncode if child else None, "timed_out": timed_out,
            "stdout": bytes(output["stdout"]), "stderr": bytes(output["stderr"]),
            "stdout_count": counts["stdout"], "stderr_count": counts["stderr"],
            "stdout_eof": eof["stdout"], "stderr_eof": eof["stderr"],
            "stdout_closed": closed["stdout"], "stderr_closed": closed["stderr"],
            "reaped": reaped, "elapsed_s": time.monotonic() - start, **diagnostic}


def _case(root, argv):
    fixed = {
        ("/usr/bin/curl", "-q", "--version"): "curl-loader-control",
        ("/bin/cat", str(root / "allowed/seed")): "allowed-read",
        ("/usr/bin/touch", str(root / "allowed/new")): "allowed-write",
        ("/bin/cat", str(root / "decoy/seed")): "denied-read",
        ("/usr/bin/touch", str(root / "decoy/new")): "denied-write",
        ("/bin/sh", "-c", 'while :; do :; done'): "timeout-control",
    }
    for name in ("allowed", "decoy"):
        seed = str(root / name / "seed")
        for script, label in (( '( : < "$1" ) & child=$!; printf "owned-child %s %s\\n" "$$" "$child" >&2; wait "$child"', "fork-only"),
                              ( '/bin/cat "$1" & child=$!; printf "owned-child %s %s\\n" "$$" "$child" >&2; wait "$child"', "fork-exec")):
            fixed[("/bin/sh", "-c", script, "probe", seed)] = label + "-" + name
    key = tuple(argv)
    if key in fixed:
        return fixed[key]
    if (len(key) == 8 and key[:7] == ("/usr/bin/curl", "-q", "--verbose", "--noproxy", "*", "--max-time", "1")
            and re.fullmatch(r"http://127\.0\.0\.1:([1-9][0-9]{0,4})/", key[7])):
        port = int(key[7].split(":")[-1][:-1])
        if port <= 65535:
            return "denied-network"
    raise ValueError("command not frozen")


def _probe_guards(profile_path, allowed_root):
    if sys.platform != "darwin" or os.getuid() == 0:
        raise ValueError("unprivileged Darwin only")
    root = _root(allowed_root)
    if _live:
        raise ValueError("previous child not verified reaped")
    check_fixture(allowed_root)
    profile = Path(profile_path)
    fixed = Path(__file__).absolute().parent / "fixture.sb"
    if profile != fixed or profile.resolve(strict=True) != profile:
        raise ValueError("profile not fixed canonical path")
    s = profile.lstat()
    if (not stat.S_ISREG(s.st_mode) or s.st_uid != os.getuid() or s.st_nlink != 1
            or stat.S_IMODE(s.st_mode) & 0o022):
        raise ValueError("unsafe profile ownership")
    if hashlib.sha256(profile.read_bytes()).hexdigest() != PROFILE_SHA256:
        raise ValueError("profile hash mismatch")
    return root, profile


def run_probe(profile_path, allowed_root, argv, deadline_s=2):
    root, profile = _probe_guards(profile_path, allowed_root)
    case = _case(root, argv)
    return _execute(["/usr/bin/sandbox-exec", "-f", str(profile), "-D",
                     "ALLOWED_ROOT=" + str(root / "allowed"), *argv], case, deadline_s)


def run_startup_control(profile_path, allowed_root, sandboxed, deadline_s=2):
    """Fixed EOF controls; both modes enforce the complete probe guards."""
    if type(sandboxed) is not bool:
        raise ValueError("startup mode must be bool")
    root, profile = _probe_guards(profile_path, allowed_root)
    argv = ["/bin/cat"]
    if sandboxed:
        argv = ["/usr/bin/sandbox-exec", "-f", str(profile), "-D",
                "ALLOWED_ROOT=" + str(root / "allowed"), *argv]
    return _execute(argv, "sandbox-eof" if sandboxed else "direct-eof", deadline_s)
