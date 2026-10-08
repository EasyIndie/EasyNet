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


def _execute(argv, case, deadline_s=2):
    """Internal fixed commands only; retain capped output while draining pipes."""
    start = time.monotonic()
    if not 0 < deadline_s <= 2:
        raise ValueError("invalid deadline")
    end = start + deadline_s
    output = {"stdout": bytearray(), "stderr": bytearray()}
    counts = {"stdout": 0, "stderr": 0}
    timed_out = False
    reaped = False
    selector = child = None
    def send(sig):
        try:
            os.killpg(child.pid, sig)
        except ProcessLookupError:
            pass
    try:
        selector = selectors.DefaultSelector()
        child = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, env=_environment(),
                                 close_fds=True, start_new_session=True, umask=0o077)
        _live.add(child.pid)
        for name, stream in (("stdout", child.stdout), ("stderr", child.stderr)):
            os.set_blocking(stream.fileno(), False)
            selector.register(stream, selectors.EVENT_READ, name)
        sent_term = sent_kill = False
        while True:
            now = time.monotonic()
            # WNOWAIT keeps the owned leader PID reserved until group cleanup.
            exited = os.waitid(os.P_PID, child.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
            if not sent_term and (now >= end - 0.35 or exited):
                timed_out = not bool(exited)
                send(signal.SIGTERM)
                sent_term = True
            if not sent_kill and (now >= end - 0.2 or exited):
                send(signal.SIGKILL)
                sent_kill = True
            for key, _ in selector.select(max(0, min(0.02, end - now))):
                data = os.read(key.fileobj.fileno(), 4096)
                if not data:
                    selector.unregister(key.fileobj)
                else:
                    name = key.data
                    counts[name] += len(data)
                    output[name].extend(data[:max(0, CAP - len(output[name]))])
            if exited and not selector.get_map():
                break
            if time.monotonic() >= end:
                timed_out = True
                break
        child.wait(timeout=max(0, end - time.monotonic()))
        # Any surviving owned descendant is a failure, never a qualified denial.
        try:
            os.killpg(child.pid, 0)
        except ProcessLookupError:
            reaped = True
            _live.discard(child.pid)
    except (OSError, subprocess.TimeoutExpired):
        timed_out = True
    finally:
        # Signal only while the unreaped leader still reserves its group identity.
        try:
            if child is not None and child.returncode is None:
                try:
                    send(signal.SIGKILL)
                    child.wait(timeout=max(0, end - time.monotonic()))
                except (OSError, subprocess.TimeoutExpired):
                    pass
        finally:
            try:
                if selector is not None:
                    selector.close()
            finally:
                if child is not None:
                    try:
                        child.stdout.close()
                    finally:
                        child.stderr.close()
    return {"case": case, "returncode": child.returncode if child else None, "timed_out": timed_out,
            "stdout": bytes(output["stdout"]), "stderr": bytes(output["stderr"]),
            "stdout_count": counts["stdout"], "stderr_count": counts["stderr"],
            "reaped": reaped, "elapsed_s": time.monotonic() - start}


def _case(root, argv):
    fixed = {
        ("/usr/bin/curl", "-q", "--version"): "curl-loader-control",
        ("/bin/cat", str(root / "allowed/seed")): "allowed-read",
        ("/usr/bin/touch", str(root / "allowed/new")): "allowed-write",
        ("/bin/cat", str(root / "decoy/seed")): "denied-read",
        ("/usr/bin/touch", str(root / "decoy/new")): "denied-write",
        ("/bin/sh", "-c", '/bin/cat "$1"', "probe", str(root / "decoy/seed")): "inherited-read",
    }
    key = tuple(argv)
    if key in fixed:
        return fixed[key]
    if (len(key) == 8 and key[:7] == ("/usr/bin/curl", "-q", "--verbose", "--noproxy", "*", "--max-time", "1")
            and re.fullmatch(r"http://127\.0\.0\.1:([1-9][0-9]{0,4})/", key[7])):
        port = int(key[7].split(":")[-1][:-1])
        if port <= 65535:
            return "denied-network"
    raise ValueError("command not frozen")


def run_probe(profile_path, allowed_root, argv, deadline_s=2):
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
    case = _case(root, argv)
    return _execute(["/usr/bin/sandbox-exec", "-f", str(profile), "-D",
                     "ALLOWED_ROOT=" + str(root / "allowed"), *argv], case, deadline_s)
