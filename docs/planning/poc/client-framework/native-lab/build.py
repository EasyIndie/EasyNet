"""Compile-only candidate. CLI is inert until a separately reviewed binding exists."""
import errno
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import selectors
import shlex
import signal
import stat
import struct
import subprocess
import time
import uuid

P = "docs/planning/poc/client-framework/native-lab"
FILES = {f"{P}/Host.swift": 8192, f"{P}/Info.plist": 4096,
         f"{P}/build.py": 40960, f"{P}/Tests/test_build.py": 40960,
         ".github/workflows/g0-client-native-build.yml": 8192}
DEV = Path("/Applications/Xcode_16.4.app/Contents/Developer")
SWIFT = DEV / "Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
SDK = DEV / "Platforms/MacOSX.platform/Developer/SDKs/MacOSX15.5.sdk"
BASE = {"os": "15.7.9", "build": "24G830", "arch": "arm64",
        "image_os": "macos15", "image_version": "20260907.0337.1",
        "xcode": "Xcode 16.4\nBuild version 16F6", "sdk_version": "15.5"}
REQUIRED = ("-parse-as-library", "-emit-executable", "-swift-version",
            "-target", "-sdk", "-module-cache-path", "-module-name", "-framework")
BINDING_PATH = "docs/planning/task-bindings/native-build-runtime.json"
TOPS = ["app", "module-cache", "result", "src", "tmp"]


class Reject(Exception):
    def __init__(self, code):
        self.code = code


def require(ok, code):
    if not ok:
        raise Reject(code)


def regular(path, maximum, mode=None, deadline=float("inf")):
    checkpoint(deadline)
    """Reject link components and bound reads before opening with O_NOFOLLOW."""
    path = Path(path).absolute()
    for parent in (path, *path.parents):
        require(not parent.is_symlink(), "source-mismatch")
    info = path.lstat()
    require(stat.S_ISREG(info.st_mode) and info.st_size <= maximum, "source-mismatch")
    if mode is not None:
        require(stat.S_IMODE(info.st_mode) == mode, "source-mismatch")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        require(os.fstat(fd) == info, "source-mismatch")
        data = os.read(fd, maximum + 1)
        require(len(data) == info.st_size and len(data) <= maximum, "source-mismatch")
        checkpoint(deadline)
        return data
    finally:
        os.close(fd)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def sources(repo, binding, deadline=float("inf")):
    checkpoint(deadline)
    require(isinstance(binding, dict) and binding.get("schema") == 1, "source-mismatch")
    for name, size in (("feature", 40), ("workflow", 64), ("contract", 64), ("manifest", 64)):
        require(bool(re.fullmatch(r"[0-9a-f]{" + str(size) + r"}", binding.get(name, "")))
                and set(binding[name]) != {"0"}, "source-mismatch")
    require(binding.get("checkout") == binding["feature"], "source-mismatch")
    manifest = binding.get("sources", {})
    require(set(manifest) == set(FILES), "source-mismatch")
    require(digest(json.dumps(manifest, sort_keys=True, separators=(",", ":")).encode())
            == binding["manifest"], "source-mismatch")
    verified = {}
    for name, maximum in FILES.items():
        checkpoint(deadline)
        item = manifest[name]
        require(set(item) == {"sha256", "size", "mode", "type"}
                and item["type"] == "regular" and item["mode"] == 0o644, "source-mismatch")
        data = regular(repo / name, maximum, item["mode"], deadline)
        require(len(data) == item["size"] and digest(data) == item["sha256"], "source-mismatch")
        verified[name] = data
    require(digest(verified[".github/workflows/g0-client-native-build.yml"])
            == binding["workflow"], "source-mismatch")
    contract = regular(repo / "docs/planning/poc/client-framework/native-build-contract.md", 32768, deadline=deadline)
    require(digest(contract) == binding["contract"], "source-mismatch")
    return verified


def environment(root):
    env = {"PATH": "/usr/bin:/bin", "LC_ALL": "C", "DEVELOPER_DIR": str(DEV),
           "TMPDIR": str(root / "tmp")}
    for name in ("HOME", "CODEX_HOME"):
        if name in os.environ:
            env[name] = os.environ[name]
    return env


class Cancellation:
    def __init__(self):
        self.cancelled = False
        self.previous = {}

    def __enter__(self):
        require(signal.getsignal(signal.SIGCHLD) == signal.SIG_DFL, "cleanup")
        for sig in (signal.SIGTERM, signal.SIGINT):
            self.previous[sig] = signal.getsignal(sig)
            signal.signal(sig, self.mark)
        return self

    def mark(self, *_):
        self.cancelled = True

    def __exit__(self, *_):
        for sig, handler in self.previous.items():
            signal.signal(sig, handler)


def checkpoint(deadline, cancel=None):
    require(cancel is None or not cancel.cancelled, "cancelled")
    require(time.monotonic() < deadline, "timeout")


def capture(argv, root, env, whole, budget, records, cancel=None):
    """14s metadata has 10s work + 2s TERM + 2s KILL/drain/reap allowance."""
    if cancel is None:
        with Cancellation() as local:
            return capture(argv, root, env, whole, budget, records, local)
    end = min(whole, time.monotonic() + budget)
    rec = {"command": len(records), "exit": None, "deadline": budget, "bytes": [0, 0],
           "drained": False, "fd_closed": False, "reaped": False, "cancelled": False,
           "group_observation": "not-requested", "ownership": "not-spawned",
           "primary_error": "none", "group_stage": "none", "group_errno": "none"}
    records.append(rec)
    proc = None
    sel = selectors.DefaultSelector()
    chunks = [bytearray(), bytearray()]
    error = None
    def drain(until, stop_on_fault):
        while sel.get_map() and time.monotonic() < until:
            for key, _ in sel.select(min(0.05, max(0, until - time.monotonic()))):
                data = os.read(key.fileobj.fileno(), 8192)
                index = key.data
                if not data:
                    sel.unregister(key.fileobj)
                else:
                    rec["bytes"][index] += len(data)
                    chunks[index].extend(data[:max(0, 65536 - len(chunks[index]))])
            if stop_on_fault:
                checkpoint(until, cancel)
                require(max(rec["bytes"]) <= 65536, "overflow")
        rec["drained"] = not sel.get_map()
    def owned_signal(sig):
        stage = "identity"
        try:
            require(proc.returncode is None and rec["ownership"] == "held"
                    and signal.getsignal(signal.SIGCHLD) == signal.SIG_DFL, "cleanup")
            require(os.getpgid(proc.pid) == proc.pid, "cleanup")
            stage = "term" if sig == signal.SIGTERM else "kill"
            os.killpg(proc.pid, sig)
        except (OSError, Reject) as exc:
            if rec["group_stage"] == "none":
                rec["group_stage"] = stage
                number = getattr(exc, "errno", None)
                rec["group_errno"] = ("absent" if number == errno.ESRCH else "permission"
                                      if number in (errno.EPERM, errno.EACCES) else
                                      "other" if isinstance(exc, OSError) else "none")
            raise
        rec["group_observation"] = "signals-issued-unproven"
    try:
        checkpoint(end - 4, cancel)
        proc = subprocess.Popen(argv, cwd=root, env=env, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        require(os.getpgid(proc.pid) == proc.pid, "cleanup")
        rec["ownership"] = "held"
        for index, stream in enumerate((proc.stdout, proc.stderr)):
            os.set_blocking(stream.fileno(), False)
            sel.register(stream, selectors.EVENT_READ, index)
        # No poll/wait before EOF: inherited writers may still hold the pipes.
        drain(end - 4, True)
        require(rec["drained"], "timeout")
        checkpoint(end - 4, cancel)
        try:
            proc.wait(timeout=max(0.001, end - 4 - time.monotonic()))
        except subprocess.TimeoutExpired:
            raise Reject("timeout") from None
        rec["reaped"] = True
        rec["ownership"] = "released"
    except Reject as exc:
        error = exc.code
        if proc is not None and rec["ownership"] == "not-spawned":
            rec["group_stage"] = "identity"
    except KeyboardInterrupt:
        cancel.mark()
        error = "cancelled"
    except (OSError, ValueError) as exc:
        error = "spawn" if proc is None else "cleanup"
        if proc is not None and rec["ownership"] == "not-spawned":
            rec["group_stage"] = "identity"
            rec["group_errno"] = ("absent" if getattr(exc, "errno", None) == errno.ESRCH else
                                  "permission" if getattr(exc, "errno", None) in (errno.EPERM, errno.EACCES)
                                  else "other")
    finally:
        rec["primary_error"] = error or "none"
        rec["cancelled"] = cancel.cancelled
        if proc is not None:
            if not rec["reaped"]:
                try:
                    owned_signal(signal.SIGTERM)
                    drain(end - 2, False)
                    if rec["drained"]:
                        try:
                            proc.wait(timeout=max(0, end - 2 - time.monotonic()))
                            rec["reaped"] = True
                            rec["ownership"] = "released"
                        except subprocess.TimeoutExpired:
                            pass
                    if not rec["reaped"]:
                        owned_signal(signal.SIGKILL)
                except (OSError, ValueError, Reject):
                    rec["ownership"] = "ambiguous"
                    error = "cleanup"
                # Group signaling failure must never skip direct-child cleanup.
                try:
                    drain(end, False)
                except (OSError, ValueError, Reject):
                    error = "cleanup"
                try:
                    if not rec["reaped"]:
                        proc.wait(timeout=max(0, end - time.monotonic()))
                        rec["reaped"] = True
                        rec["ownership"] = "released"
                except (OSError, Reject, subprocess.TimeoutExpired):
                    rec["ownership"] = "ambiguous"
                    error = "cleanup"
            rec["exit"] = proc.returncode
            for stream in (proc.stdout, proc.stderr):
                if stream is not None:
                    try:
                        stream.close()
                    except OSError:
                        error = "cleanup"
        sel.close()
        rec["cancelled"] = cancel.cancelled
        rec["fd_closed"] = proc is None or all(stream is None or stream.closed
                                               for stream in (proc.stdout, proc.stderr))
    if error:
        raise Reject(error)
    rec["primary_error"] = ("overflow" if max(rec["bytes"]) > 65536 else
                            ("compile" if budget == 120 else "tool-unavailable") if rec["exit"] != 0 else "none")
    require(rec["primary_error"] == "none", rec["primary_error"])
    try:
        return bytes(chunks[0]).decode("utf-8", errors="strict").strip()
    except UnicodeDecodeError:
        rec["primary_error"] = "identity"
        raise Reject("identity") from None


def driver_jobs(text, logical_sdk, canonical_sdk):
    """Keep semantic planned forwarding only; never run or retain printed argv."""
    require(all(isinstance(value, str) for value in (text, logical_sdk, canonical_sdk)), "plan-format")
    try:
        require(len(text.encode("utf-8", errors="strict")) <= 65536 and "\0" not in text, "plan-format")
        lines = [line for line in text.splitlines() if line.strip()]
        require(1 <= len(lines) <= 8, "plan-format")
        jobs = []
        relevant = r"^(?:--?target|-sdk|-isysroot|-syslibroot|-platform_version)"
        flags = dict.fromkeys(("-sdk", "-isysroot", "-syslibroot"), "sdk")
        flags.update({"-target": "target", "--target": "target", "-platform_version": "platform_version_present"})
        for line in lines:
            tokens = shlex.split(line, posix=True, comments=False)
            require(1 <= len(tokens) <= 512 and tokens[0] and not tokens[0].startswith("-"), "plan-format")
            require(all(len(token.encode("utf-8")) <= 4096 and not token.startswith("@")
                        and token != "-filelist" for token in tokens), "plan-format")
            tool = Path(tokens[0]).name
            job = {"tool": {"swift-frontend": "frontend", "clang": "clang", "ld": "ld"}.get(tool, "other"),
                   "target": "absent", "sdk": "absent", "platform_version_present": False}
            index = 1
            frontend_sdk_seen = False
            while index < len(tokens):
                token = tokens[index]
                operands = []
                category = None
                wrapped_parts = []
                if token == "-target-sdk-version":
                    require(tool == "swift-frontend" and not frontend_sdk_seen
                            and index + 1 < len(tokens) and tokens[index + 1]
                            and not tokens[index + 1].startswith(("-", "@")), "plan-format")
                    frontend_sdk_seen, index = True, index + 2
                elif token.startswith("-X"):
                    require(index + 1 < len(tokens) and tokens[index + 1], "plan-format")
                    wrapped = tokens[index + 1]
                    if token == "-Xlinker" and wrapped == "-platform_version":
                        require(tokens[index:index + 8:2] == ["-Xlinker"] * 4
                                and len(tokens[index:index + 8]) == 8, "plan-format")
                        operands = tokens[index + 3:index + 8:2]
                        category, index = "platform_version_present", index + 8
                    else:
                        wrapped_parts = wrapped.split(",")
                        index += 2
                elif token.startswith("-") and "," in token and not token.startswith("--target="):
                    parts = token.split(",")
                    if parts[0] == "-Wl" and parts[1] == "-platform_version":
                        require(len(parts) == 5, "plan-format")
                        operands, category = parts[2:], "platform_version_present"
                    else:
                        wrapped_parts = parts
                    index += 1
                elif token in flags:
                    category = flags[token]
                    count = 3 if category == "platform_version_present" else 1
                    operands = tokens[index + 1:index + 1 + count]
                    require(len(operands) == count, "plan-format")
                    index += count + 1
                elif token.startswith("--target="):
                    operands, category = [token[len("--target="):]], "target"
                    index += 1
                else:
                    require(not re.match(relevant, token), "plan-format")
                    index += 1
                require(not any(re.match(relevant, part) or part.startswith("@") or part == "-filelist"
                                for part in wrapped_parts), "plan-format")
                if category is not None:
                    require(all(value and not value.startswith(("-", "@")) for value in operands)
                            and job[category] in ("absent", False), "plan-format")
                    values = ({"arm64-apple-macosx15.0": "expected"} if category == "target" else
                              {canonical_sdk: "qualified-canonical", logical_sdk: "qualified-logical"})
                    job[category] = True if category == "platform_version_present" else values.get(operands[0], "other")
            jobs.append(job)
        return jobs
    except (UnicodeError, ValueError):
        raise Reject("plan-format") from None


def entry_hash(path, deadline):
    """Selected vendor entry: explicitly bounded 512MiB streaming observation."""
    try:
        info = path.lstat()
        def stable(value):
            return (value.st_dev, value.st_ino, value.st_mode, value.st_size,
                    value.st_mtime_ns, value.st_ctime_ns)
        require(stat.S_ISREG(info.st_mode) and 0 < info.st_size <= 512 * 1024 * 1024, "identity")
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(fd, "rb") as stream:
            require(stable(os.fstat(stream.fileno())) == stable(info), "identity")
            hashed = hashlib.sha256()
            total = 0
            while True:
                checkpoint(deadline)
                chunk = stream.read(1024 * 1024)
                if not chunk:
                    break
                total += len(chunk)
                require(total <= info.st_size, "identity")
                hashed.update(chunk)
            require(total == info.st_size and stable(os.fstat(stream.fileno())) == stable(info), "identity")
        return hashed.hexdigest(), total
    except OSError:
        raise Reject("identity") from None


def identity(run, observed, deadline=float("inf")):
    for key, expected in BASE.items():
        require(observed.get(key) == expected, "identity")
    compiler = Path(run(["/usr/bin/xcrun", "--toolchain", "XcodeDefault", "--find", "swiftc"]))
    sdk = Path(run(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path"]))
    try:
        require(compiler == SWIFT and sdk.resolve(strict=True) == SDK.resolve(strict=True)
                and sdk.resolve().is_dir(), "identity")
    except OSError:
        raise Reject("identity") from None
    for path in (compiler, sdk):
        require(path.resolve().is_relative_to(DEV.resolve()), "identity")
    sha, size = entry_hash(compiler.resolve(strict=True), deadline)
    version = run([str(compiler), "--version"])
    require(0 < len(version.encode()) <= 2048 and all(c == "\n" or 32 <= ord(c) <= 126
                                                    for c in version), "identity")
    help_text = run([str(compiler), "-help"])
    require(all(re.search(r"(?<![\w-])" + re.escape(flag) + r"(?![\w-])", help_text)
                for flag in REQUIRED), "flags")
    return {"path": str(compiler), "hash_path": str(compiler.resolve()),
            "version": version, "sha256": sha, "size": size}, SDK


def artifact(executable, plist, deadline=float("inf"), out=None):
    if out is None:
        out = {}
    out["artifact_predicate"] = "file-mode-bounds"
    out["artifact_sdk_version"] = None
    checkpoint(deadline)
    try:
        data = regular(executable, 32 * 1024 * 1024, 0o700, deadline)
    except Reject as exc:
        if exc.code == "timeout":
            raise
        raise Reject("artifact") from None
    except OSError:
        raise Reject("artifact") from None
    out["artifact_predicate"] = "header-length"
    require(len(data) >= 32, "artifact")
    out["artifact_predicate"] = "header-fields"
    magic, cpu, _, kind, count, size, _, _ = struct.unpack_from("<8I", data)
    require(magic == 0xFEEDFACF and cpu == 0x100000C and kind == 2
            and 0 < count <= 4096 and 8 * count <= size <= len(data) - 32, "artifact")
    offset = 32
    build = 0
    segments = []
    entry = None
    for _ in range(count):
        checkpoint(deadline)
        out["artifact_predicate"] = "command-header"
        require(offset + 8 <= 32 + size, "artifact")
        command, length = struct.unpack_from("<2I", data, offset)
        out["artifact_predicate"] = "command-length"
        require(length >= 8 and length % 8 == 0 and offset + length <= 32 + size, "artifact")
        if command == 0x32:
            out["artifact_predicate"] = "build-length"
            require(length >= 24, "artifact")
            out["artifact_predicate"] = "build-fields"
            platform, minimum, sdk, tools = struct.unpack_from("<4I", data, offset + 8)
            major = sdk >> 16
            out["artifact_sdk_version"] = ({"major": major, "minor": (sdk >> 8) & 255,
                                            "patch": sdk & 255} if major <= 255 else None)
            out["artifact_build_mismatches"] = {"platform": platform != 1,
                "minimum": minimum != 0xF0000, "sdk": sdk != 0xF0500,
                "length": length != 24 + 8 * tools}
            require(platform == 1 and minimum == 0xF0000 and sdk == 0xF0500
                    and length == 24 + 8 * tools, "artifact")
            build += 1
        if command == 0x19:
            out["artifact_predicate"] = "segment-length"
            require(length >= 72, "artifact")
            out["artifact_predicate"] = "segment-bounds"
            _, _, _, vm, vm_size, file_at, file_size, maxprot, prot, sections, _ = struct.unpack_from("<II16sQQQQiiII", data, offset)
            require(length == 72 + 80 * sections and file_at + file_size <= len(data)
                    and file_size <= vm_size and 0 <= prot <= maxprot <= 7
                    and prot & ~maxprot == 0, "artifact")
            if file_size:
                out["artifact_predicate"] = "segment-overlap"
                require(all(file_at + file_size <= a or file_at >= z for a, z, _ in segments), "artifact")
                segments.append((file_at, file_at + file_size, prot))
            for index in range(sections):
                out["artifact_predicate"] = "section-vm"
                section = offset + 72 + 80 * index
                address, section_size, section_at = struct.unpack_from("<QQI", data, section + 32)
                flags = struct.unpack_from("<I", data, section + 64)[0]
                require(vm <= address <= vm + vm_size and section_size <= vm + vm_size - address, "artifact")
                if flags & 0xFF not in (1, 0xC, 0x12):
                    out["artifact_predicate"] = "section-file"
                    require(file_at <= section_at and section_at + section_size <= file_at + file_size, "artifact")
        if command == 0x80000028:
            out["artifact_predicate"] = "entry-command"
            require(length == 24 and entry is None, "artifact")
            entry, _ = struct.unpack_from("<QQ", data, offset + 8)
        offset += length
    out["artifact_predicate"] = "entry-bounds"
    require(offset == 32 + size and build == 1 and entry is not None
            and any(a <= entry < z and prot & 4 for a, z, prot in segments)
            and entry >= 32 + size, "artifact")
    try:
        out["artifact_predicate"] = "plist-read"
        metadata = plistlib.loads(regular(plist, 4096, 0o600, deadline))
    except (Reject, OSError, ValueError, plistlib.InvalidFileException):
        raise Reject("artifact") from None
    out["artifact_predicate"] = "plist-content"
    require(metadata == {"CFBundlePackageType": "APPL", "CFBundleExecutable": executable.name,
            "CFBundleIdentifier": "com.example.easynet.native-lab", "CFBundleName": "EasyNet Native Lab",
            "CFBundleVersion": "0.0.1", "CFBundleShortVersionString": "0.0.1",
            "LSMinimumSystemVersion": "15.0"}, "artifact")
    out["artifact_predicate"] = "passed"
    return {"sha256": digest(data), "size": len(data)}


def inventory(root, tops, deadline=float("inf")):
    entries = []
    total = 0
    def visit(path):
        nonlocal total
        checkpoint(deadline)
        info = path.lstat()
        require(info.st_uid == os.getuid() and not stat.S_ISLNK(info.st_mode), "cleanup")
        require(stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode), "cleanup")
        total += info.st_size if stat.S_ISREG(info.st_mode) else 0
        require(len(entries) < 2048 and total <= 128 * 1024 * 1024, "cleanup")
        entry = {"path": str(path.relative_to(root)), "inode": info.st_ino,
                 "type": "directory" if stat.S_ISDIR(info.st_mode) else "regular"}
        entries.append(entry)
        if stat.S_ISREG(info.st_mode):
            entry["sha256"] = digest(regular(path, 32 * 1024 * 1024, deadline=deadline))
            entry["size"] = info.st_size
        else:
            for child in sorted(path.iterdir()):
                visit(child)
    for top in sorted(tops):
        visit(root / top)
    return entries


def cleanup(root, owner, inode, expected, deadline=float("inf")):
    checkpoint(deadline)
    require(not root.is_symlink(), "cleanup")
    info = root.lstat()
    require(info.st_uid == owner and info.st_ino == inode, "cleanup")
    current = inventory(root, sorted(p.name for p in root.iterdir()), deadline)
    require(current == expected, "cleanup")
    for entry in reversed(current):
        checkpoint(deadline)
        path = root / entry["path"]
        info = path.lstat()
        require(info.st_uid == owner and info.st_ino == entry["inode"], "cleanup")
        if entry["type"] == "directory":
            path.rmdir()
        else:
            path.unlink()
    root.rmdir()


def result():
    return {"schema": 1, "phase": "compile", "result": "rejected", "error": "source-mismatch",
            "feature": None, "workflow": None, "contract": None, "manifest": None,
            "run_token": None, "baseline": {}, "compiler": None, "sdk": None, "sources": {},
            "driver_jobs": None, "artifact": None, "artifact_predicate": "not-run", "commands": [], "generated": None, "cleanup": "not-created",
            "primary-error": "none", "artifact_build_mismatches": None, "artifact_sdk_version": None,
            "external-effects": "trusted-vendor-not-denied", "candidate-executed": False,
            "gui": "not-run", "engine": "not-run", "ne": "not-run"}


def adoption(root, expected, deadline):
    require(sorted(p.name for p in root.iterdir()) == TOPS, "cleanup")
    current = inventory(root, TOPS, deadline)
    def fixed(items):
        return [item for item in items if item["path"].split("/")[0] in ("src", "result")
                or item["path"].endswith("/Info.plist")]
    require(fixed(current) == fixed(expected), "cleanup")
    return current


def build(repo, binding):
    with Cancellation() as cancel:
        return build_owned(repo, binding, cancel)


def build_owned(repo, binding, cancel):
    out = result()
    whole = time.monotonic() + 180
    root = None
    expected = None
    try:
        require(isinstance(binding, dict), "source-mismatch")
        diagnostic = binding.get("grant") == "one-driver-jobs-only"
        require(diagnostic == (binding.get("qualification") == "sdk-driver-jobs-hosted19-v1"), "identity")
        out["phase"] = "driver-jobs" if diagnostic else "compile"
        data = sources(Path(repo), binding, whole - 4)
        out.update({name: binding[name] for name in ("feature", "workflow", "contract", "manifest")})
        out["sources"] = {name: digest(value) for name, value in data.items()}
        require((diagnostic or binding.get("grant") == "one-compile-only") and binding.get("python_verified") is True,
                "identity")  # Trusted pre-import launcher must independently enforce both.
        token = uuid.uuid4().hex
        parent = Path("/private/tmp")
        require(parent.resolve() == parent and not parent.is_symlink(), "cleanup")
        root = parent / ("easynet-qb-build-" + token)
        root.mkdir(mode=0o700)
        owner, inode = root.stat().st_uid, root.stat().st_ino
        out["run_token"] = token
        checkpoint(whole - 4, cancel)
        for name in ("src", "tmp", "module-cache", "app", "result", "app/EasyNetNativeLab.app",
                     "app/EasyNetNativeLab.app/Contents", "app/EasyNetNativeLab.app/Contents/MacOS"):
            (root / name).mkdir(mode=0o700)
        for name, target in (("Host.swift", root / "src/Host.swift"),
                             ("Info.plist", root / "app/EasyNetNativeLab.app/Contents/Info.plist")):
            fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            with os.fdopen(fd, "wb") as stream:
                stream.write(data[f"{P}/{name}"])
            checkpoint(whole - 4, cancel)
            require(digest(regular(target, 8192, 0o600, whole - 4)) == digest(data[f"{P}/{name}"]), "source-mismatch")
        expected = inventory(root, sorted(p.name for p in root.iterdir()), whole - 4)
        env = environment(root)
        def run(argv, budget=14):
            nonlocal expected
            checkpoint(whole - 4, cancel)
            require(expected is not None, "cleanup")
            try:
                return capture(argv, root, env, whole, budget, out["commands"], cancel)
            finally:
                record = out["commands"][-1] if out["commands"] else {}
                if record.get("reaped") and record.get("drained") and record.get("fd_closed"):
                    try:
                        expected = adoption(root, expected, whole - 1)
                    except Reject:
                        expected = None  # Preserve primary capture error; retain tree.
                else:
                    expected = None
        observed = {"os": run(["/usr/bin/sw_vers", "-productVersion"]),
                    "build": run(["/usr/bin/sw_vers", "-buildVersion"]),
                    "arch": run(["/usr/bin/uname", "-m"]),
                    "xcode": run([str(DEV / "usr/bin/xcodebuild"), "-version"]),
                    "sdk_version": run(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-version"]),
                    "image_os": os.environ.get("ImageOS"), "image_version": os.environ.get("ImageVersion")}
        require(all(observed.get(k) == v for k, v in BASE.items()), "identity")
        out["baseline"] = dict(BASE)
        compiler, sdk = identity(run, observed, whole - 4)
        out["compiler"], out["sdk"] = compiler, {"path": str(sdk), "version": "15.5"}
        executable = root / "app/EasyNetNativeLab.app/Contents/MacOS/EasyNetNativeLab"
        argv = [compiler["path"], "-parse-as-library", "-emit-executable", "-swift-version", "6", "-Onone",
             "-target", "arm64-apple-macosx15.0", "-sdk", str(sdk), "-module-cache-path",
             str(root / "module-cache"), "-module-name", "EasyNetNativeLab", "-framework", "SwiftUI",
             "-framework", "AppKit", "-framework", "Foundation", str(root / "src/Host.swift"),
             "-o", str(executable)]
        planned = run(argv + (["-driver-print-jobs"] if diagnostic else []), 120)
        if diagnostic:
            require(expected is not None, "cleanup")
            observations = driver_jobs(planned, str(sdk), str(sdk.resolve(strict=True)))
            checkpoint(whole - 4, cancel)
            out.update(result="planned", error="none", driver_jobs=observations)
            return out
        out["artifact_predicate"] = "file-preflight"
        try:
            regular(executable, 32 * 1024 * 1024, deadline=whole - 4)
        except (Reject, OSError):
            raise Reject("artifact") from None
        os.chmod(executable, 0o700, follow_symlinks=False)
        out["artifact"] = artifact(executable, root / "app/EasyNetNativeLab.app/Contents/Info.plist", whole - 4, out)
        out["generated"] = digest(json.dumps(inventory(root, ["tmp", "module-cache", "app"], whole - 4),
                                            sort_keys=True, separators=(",", ":")).encode())
        expected = inventory(root, sorted(p.name for p in root.iterdir()), whole - 4)
        checkpoint(whole - 4, cancel)
        out.update(result="compiled", error="none")
    except Reject as exc:
        out.update(result="rejected" if exc.code in ("source-mismatch", "identity", "flags") else "failed",
                   error=exc.code)
    except (Exception, KeyboardInterrupt):
        out.update(result="failed", error="internal")
    finally:
        if root is not None:
            try:
                require(expected is not None, "cleanup")
                cleanup(root, owner, inode, expected, whole)
                out["cleanup"] = "removed"
            except Exception:
                out.update(result="failed", **{"primary-error": out["error"]}, error="cleanup", cleanup="retained")
    return out


def emit(out):
    encoded = json.dumps(out, sort_keys=True, separators=(",", ":"))
    if len(encoded.encode()) > 16384:
        phase = out.get("phase")
        predicate = out.get("artifact_predicate")
        if predicate not in ("not-run", "file-preflight", "file-mode-bounds", "header-length",
                             "header-fields", "command-header", "command-length", "build-length",
                             "build-fields", "segment-length", "segment-bounds", "segment-overlap",
                             "section-vm", "section-file", "entry-command", "entry-bounds",
                             "plist-read", "plist-content", "passed"):
            predicate = "not-run"
        mismatches = out.get("artifact_build_mismatches")
        sdk_version = out.get("artifact_sdk_version")
        out = result()
        out["phase"] = "driver-jobs" if phase == "driver-jobs" else "compile"
        if (isinstance(mismatches, dict) and set(mismatches) == {"platform", "minimum", "sdk", "length"}
                and all(type(value) is bool for value in mismatches.values())):
            out["artifact_build_mismatches"] = mismatches
        if (isinstance(sdk_version, dict) and set(sdk_version) == {"major", "minor", "patch"}
                and all(type(value) is int and 0 <= value <= 255 for value in sdk_version.values())):
            out["artifact_sdk_version"] = {key: sdk_version[key] for key in ("major", "minor", "patch")}
        out["artifact_predicate"] = predicate
        out.update(result="failed", error="overflow", cleanup="unknown")
        encoded = json.dumps(out, sort_keys=True, separators=(",", ":"))
    print(encoded)


def main():
    # Trusted immutable workflow verifies binding/source identity BEFORE this import.
    repo = Path(__file__).absolute().parents[5]
    try:
        binding = json.loads(regular(repo / BINDING_PATH, 16384, 0o644))
        require(binding.get("status") == "frozen", "source-mismatch")
        emit(build(repo, binding))
    except (Exception, KeyboardInterrupt):
        emit(result())


if __name__ == "__main__":
    main()
