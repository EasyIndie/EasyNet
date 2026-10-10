"""Trusted vendor metadata observer; source proposal, no runtime binding."""
import json
import os
import re
import selectors
import signal
import subprocess
import time

COMMANDS = (
    ("os-version", ("/usr/bin/sw_vers", "-productVersion")),
    ("os-build", ("/usr/bin/sw_vers", "-buildVersion")),
    ("architecture", ("/usr/bin/uname", "-m")),
    ("xcode", ("/usr/bin/xcodebuild", "-version")),
    ("sdk", ("/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-version")),
)
ENV = {"PATH": "/usr/bin:/bin", "LANG": "C", "LC_ALL": "C"}
ERRORS = {"none", "provider", "unsupported", "start", "capture", "timeout", "cancel",
          "overflow", "nonzero", "stderr", "missing", "format", "os-major", "architecture",
          "group", "reap", "drain", "close", "schema", "internal"}
CANCELLED = False


def cancel(_number, _frame):
    global CANCELLED
    CANCELLED = True


def parse(label, raw):
    if not raw:
        return None, "missing"
    try:
        text = raw.decode("ascii")
    except UnicodeDecodeError:
        return None, "format"
    dotted = r"[0-9]{1,3}(?:\.[0-9]{1,3}){1,2}"
    build = r"[A-Za-z0-9]{1,32}"
    patterns = {"os-version": dotted, "sdk": dotted, "os-build": build,
                "architecture": r"[A-Za-z0-9_-]{1,16}",
                "xcode": "Xcode (" + dotted + ")\nBuild version (" + build + ")"}
    if label not in patterns:
        return None, "schema"
    match = re.fullmatch(patterns[label] + r"\n?", text)
    if match is None:
        return None, "format"
    value = text.removesuffix("\n")
    if label == "os-version" and value.split(".")[0] != "15":
        return None, "os-major"
    if label == "architecture" and value != "arm64":
        return None, "architecture"
    if label == "xcode":
        return {"version": match[1], "build": match[2]}, "none"
    return value, "none"


def capture(argv, deadline):
    """Natural EOF waits; abnormal cleanup signals only a still-owned leader."""
    proof = {"child": "not-started", "group": "unknown", "drain": False, "fds": False}
    child = reader = None
    streams = {"stdout": bytearray(), "stderr": bytearray()}
    total = 0
    error = "none"
    cleanup_errors = []
    code = None
    finished = False
    ownership = "held"

    def attempt(label, action):
        try:
            action()
            return True
        except BaseException:
            cleanup_errors.append(label)
            return False

    def drain(wait):
        nonlocal total, error
        for key, _ in reader.select(wait):
            block = os.read(key.fd, 4096)
            if not block:
                reader.unregister(key.fileobj)
            else:
                total += len(block)
                if total <= 4096:
                    streams[key.data].extend(block)
                elif error == "none":
                    error = "overflow"

    def group(number):
        try:
            os.killpg(child.pid, number)
        except ProcessLookupError:
            pass

    try:
        if signal.getsignal(signal.SIGCHLD) != signal.SIG_DFL:
            error = "unsupported"
        elif CANCELLED:
            error = "cancel"
        elif time.monotonic() >= deadline:
            error = "timeout"
        else:
            child = subprocess.Popen(argv, env=ENV, stdin=subprocess.DEVNULL,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                     start_new_session=True, close_fds=True)
            proof["child"] = "unknown"
            reader = selectors.DefaultSelector()
            for name in streams:
                stream = getattr(child, name)
                os.set_blocking(stream.fileno(), False)
                reader.register(stream, selectors.EVENT_READ, name)
            while time.monotonic() < deadline:
                if CANCELLED:
                    error = "cancel"
                    break
                drain(0.02)
                if error != "none":
                    break
                # EOF ends capture, not child or descendant ownership.
                finished = not reader.get_map()
                if finished:
                    break
            else:
                error = "timeout"
            if finished and error == "none":
                while time.monotonic() < deadline and not CANCELLED:
                    try:
                        code = child.wait(timeout=min(0.05, max(0.001, deadline - time.monotonic())))
                        ownership = "reaped"
                        proof.update(child="reaped", group="not-requested")
                        break
                    except subprocess.TimeoutExpired:
                        continue  # The direct leader remains held.
                    except BaseException:
                        ownership = "unknown"
                        cleanup_errors.append("reap")
                        break
                if CANCELLED:
                    error = "cancel"
                elif ownership == "held":
                    error = "timeout"
    except BaseException:
        error = "capture" if child is not None else "start"
    finally:
        cleanup_deadline = min(deadline + 1, time.monotonic() + 1)
        if child is not None:
            if ownership == "held":
                termed = attempt("group", lambda: group(signal.SIGTERM))
                killed = attempt("group", lambda: group(signal.SIGKILL))
                proof["group"] = "signalled" if termed and killed else "unknown"
                try:
                    code = child.wait(timeout=max(0.001, cleanup_deadline - time.monotonic()))
                    proof["child"] = "reaped"
                except BaseException:
                    ownership = "unknown"
                    cleanup_errors.append("reap")
            if reader is not None:
                try:
                    while reader.get_map() and time.monotonic() < cleanup_deadline:
                        drain(0.01)
                    proof["drain"] = not reader.get_map()
                    if not proof["drain"]:
                        cleanup_errors.append("drain")
                except BaseException:
                    cleanup_errors.append("drain")
            else:
                cleanup_errors.append("drain")
            closed = []
            if reader is not None:
                closed.append(attempt("close", reader.close))
            for stream in (child.stdout, child.stderr):
                closed.append(attempt("close", stream.close))
            proof["fds"] = all(closed)
        else:
            proof.update(group="not-started", drain=True, fds=True)
    if CANCELLED and error == "none":
        error = "cancel"
    if cleanup_errors:
        error = cleanup_errors[0]
    elif error == "none" and not finished:
        error = "internal"
    elif error == "none" and code != 0:
        error = "nonzero"
    elif error == "none" and streams["stderr"]:
        error = "stderr"
    return bytes(streams["stdout"]), error, proof


def report(provider, records, error="none"):
    value = {"schema": 1, "phase": "metadata", "result": "refused" if error != "none" else "metadata-observed",
             "error": error, "provider": provider, "commands": records, "toolchain": "not-qualified",
             "descendants": "not-proven", "external-effects": "trusted-vendor-not-denied",
             "vm-cleanup": "provider-managed-unverified"}
    try:
        if error not in ERRORS or len(records) > 5:
            raise ValueError()
        if type(provider) is not dict or set(provider) - {"ImageOS", "ImageVersion"}:
            raise ValueError()
        if any(type(v) is not str or re.fullmatch(r"[A-Za-z0-9_.-]{1,64}", v) is None for v in provider.values()):
            raise ValueError()
        if error == "none" and (len(records) != 5 or len(provider) != 2):
            raise ValueError()
        for index, record in enumerate(records):
            if type(record) is not dict or set(record) != {"command", "result", "error", "value", "cleanup"}:
                raise ValueError()
            if record["command"] != COMMANDS[index][0] or record["error"] not in ERRORS:
                raise ValueError()
            good = record["error"] == "none"
            if record["result"] != ("observed" if good else "refused"):
                raise ValueError()
            proof = record["cleanup"]
            if type(proof) is not dict or set(proof) != {"child", "group", "drain", "fds"}:
                raise ValueError()
            if proof["child"] not in {"not-started", "unknown", "reaped"} or proof["group"] not in {"not-started", "unknown", "signalled", "not-requested"}:
                raise ValueError()
            if any(type(proof[k]) is not bool for k in ("drain", "fds")):
                raise ValueError()
            if proof["group"] == "not-requested" and proof["child"] != "reaped":
                raise ValueError()
            if good and proof != dict(child="reaped", group="not-requested", drain=True, fds=True):
                raise ValueError()
            if good:
                field = record["value"]
                raw = ("Xcode " + field["version"] + "\nBuild version " + field["build"]) if index == 3 else field
                if parse(record["command"], raw.encode("ascii")) != (field, "none"):
                    raise ValueError()
            elif record["value"] is not None or index != len(records) - 1 or record["error"] != error:
                raise ValueError()
        encoded = json.dumps(value, separators=(",", ":"), ensure_ascii=True)
        if len(encoded.encode("ascii")) > 4096:
            raise ValueError()
        return encoded
    except BaseException:
        return '{"schema":1,"phase":"metadata","result":"refused","error":"schema","descendants":"not-proven","external-effects":"trusted-vendor-not-denied","vm-cleanup":"provider-managed-unverified","cleanup":"unknown"}'


def main():
    records = []
    provider = {}
    error = "none"
    overall = time.monotonic() + 90
    try:
        signal.signal(signal.SIGINT, cancel)
        signal.signal(signal.SIGTERM, cancel)
        for name in ("ImageOS", "ImageVersion"):
            item = os.environ.get(name, "")
            if re.fullmatch(r"[A-Za-z0-9_.-]{1,64}", item) is None:
                error = "provider"
                break
            provider[name] = item
        if error == "none":
            for label, argv in COMMANDS:
                raw, error, proof = capture(argv, min(overall - 6, time.monotonic() + 9))
                parsed = None
                if error == "none":
                    try:
                        parsed, error = parse(label, raw)
                    except BaseException:
                        parsed, error = None, "schema"
                records.append({"command": label, "result": "observed" if error == "none" else "refused",
                                "error": error, "value": parsed, "cleanup": proof})
                if error != "none":
                    break
    except BaseException:
        error = "internal"
    if CANCELLED and error == "none":
        error = "cancel"
    print(report(provider, records, error))
    return 0 if error == "none" else 1


if __name__ == "__main__":
    raise SystemExit(main())
