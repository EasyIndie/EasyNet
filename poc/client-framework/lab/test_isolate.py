"""Owned Darwin fixture qualification; main only, never executed by I worker."""
import importlib.util
import json
import os
from pathlib import Path
import socket
import sys
import tempfile
import threading
import time
import uuid


class Listener:
    def __init__(self, nonce):
        self.nonce = nonce
        self.count = 0
        self.errors = []
        self.stop = threading.Event()
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            self.socket.bind(("127.0.0.1", 0))
            self.socket.listen(4)
            self.socket.settimeout(0.05)
            self.port = self.socket.getsockname()[1]
            self.thread = threading.Thread(target=self.serve)
            self.thread.start()
        except BaseException:
            self.socket.close()
            raise

    def serve(self):
        while not self.stop.is_set():
            try:
                connection, _ = self.socket.accept()
            except socket.timeout:
                continue
            except OSError as error:
                if not self.stop.is_set():
                    self.errors.append(type(error).__name__)
                return
            self.count += 1
            with connection:
                connection.settimeout(0.05)
                try:
                    request = connection.recv(4096)
                    if not request.startswith(b"GET / HTTP/"):
                        raise ValueError("unexpected HTTP control request")
                    response = (b"HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: "
                                + str(len(self.nonce)).encode() + b"\r\n\r\n" + self.nonce)
                    connection.sendall(response)
                except (OSError, ValueError) as error:
                    self.errors.append(type(error).__name__)

    def close(self, end):
        self.stop.set()
        self.socket.close()
        self.thread.join(timeout=max(0, end - time.monotonic()))
        if self.thread.is_alive() or self.errors:
            raise RuntimeError("listener did not close cleanly")


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def healthy(result):
    if (not result["reaped"] or result["timed_out"] or result["elapsed_s"] > 2
            or result["stdout_count"] > 8192 or result["stderr_count"] > 8192):
        fields = ("case", "returncode", "timed_out", "reaped", "elapsed_s",
                  "stdout_count", "stderr_count", "phase", "primary_class", "primary_errno",
                  "cleanup_class", "cleanup_errno", "waitid_exit_observed", "group_check",
                  "owned_pid", "leader_wait_completed")
        diagnostic = {name: result[name] for name in fields}
        diagnostic["stderr_escaped"] = ascii(result["stderr"][:8192])[:8192]
        print(json.dumps(diagnostic, sort_keys=True))
    require(result["reaped"] and not result["timed_out"], "child outcome unqualified")
    require(result["elapsed_s"] <= 2, "command deadline exceeded")
    require(result["stdout_count"] <= 8192 and result["stderr_count"] <= 8192,
            "unexpected output overflow")


def clean_fixture(module, allowed, end):
    require(time.monotonic() < end, "cleanup deadline exhausted")
    require(not module._live, "unreaped child blocks cleanup")
    entries = module.check_fixture(allowed)
    # Validate the entire manifest before removing anything; never recurse.
    files = [path for path, value in entries.items() if not os.path.isdir(path)]
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


def main():
    end = time.monotonic() + 20
    root = listener = module = None
    passed = False
    error = None
    if sys.platform != "darwin" or os.getuid() == 0:
        print("FAIL/unknown: unprivileged Darwin required")
        return 1
    try:
        path = Path(__file__).absolute().parent / "isolate.py"
        spec = importlib.util.spec_from_file_location("fixture_isolate", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        root = Path(tempfile.mkdtemp(prefix="easynet-g0-06-isolate-", dir="/private/tmp"))
        os.chmod(root, 0o700)
        for name in ("allowed", "decoy"):
            directory = root / name
            directory.mkdir(mode=0o700)
            os.chmod(directory, 0o700)
            seed = directory / "seed"
            fd = os.open(seed, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "wb") as stream:
                stream.write(uuid.uuid4().hex.encode())
        allowed = root / "allowed"
        module.freeze_fixture(allowed)
        allowed_nonce = (allowed / "seed").read_bytes()
        decoy_nonce = (root / "decoy/seed").read_bytes()

        def run(argv, sandbox=True):
            budget = min(2, end - time.monotonic() - 0.3)
            require(budget > 0.35, "suite deadline exhausted")
            if sandbox:
                result = module.run_probe(path.parent / "fixture.sb", allowed, argv, budget)
            else:
                result = module._execute(argv, "curl-control", budget)
            healthy(result)
            return result

        read = run(["/bin/cat", str(allowed / "seed")])
        require(read["returncode"] == 0 and read["stdout"] == allowed_nonce
                and not read["stderr"], "allowed read/loader failed")
        write = run(["/usr/bin/touch", str(allowed / "new")])
        require(write["returncode"] == 0 and not write["stdout"] and not write["stderr"],
                "allowed write/loader failed")
        module.note_new(allowed)
        cases = [
            ["/bin/cat", str(root / "decoy/seed")],
            ["/usr/bin/touch", str(root / "decoy/new")],
            ["/bin/sh", "-c", '/bin/cat "$1"', "probe", str(root / "decoy/seed")],
        ]
        for argv in cases:
            denied = run(argv)
            require(denied["returncode"] == 1 and not denied["stdout"]
                    and b"Operation not permitted" in denied["stderr"]
                    and str(argv[-1]).encode() in denied["stderr"]
                    and decoy_nonce not in denied["stderr"], "ambiguous file denial")
            module.check_fixture(allowed)

        for sandbox in (False, True):
            version = run(["/usr/bin/curl", "-q", "--version"], sandbox=sandbox)
            protocols = [line.split(b":", 1)[1].split() for line in version["stdout"].splitlines()
                         if line.startswith(b"Protocols:")]
            require(version["returncode"] == 0 and protocols and b"http" in protocols[0],
                    "curl HTTP availability/loader unproven")
        http_nonce = uuid.uuid4().hex.encode()
        listener = Listener(http_nonce)
        curl = ["/usr/bin/curl", "-q", "--verbose", "--noproxy", "*", "--max-time", "1",
                f"http://127.0.0.1:{listener.port}/"]

        def reachable():
            count = listener.count
            result = run(curl, sandbox=False)
            require(result["returncode"] == 0 and result["stdout"] == http_nonce
                    and listener.count == count + 1 and not listener.errors
                    and listener.thread.is_alive(), "live listener control failed")

        reachable()
        count = listener.count
        denied = run(curl)
        eperm = {
            b"* Immediate connect fail for 127.0.0.1: Operation not permitted",
            f"* connect to 127.0.0.1 port {listener.port} failed: Operation not permitted".encode(),
        }
        require(denied["returncode"] == 7 and not denied["stdout"]
                and b"Failed to connect" in denied["stderr"]
                and bool(eperm.intersection(denied["stderr"].splitlines()))
                and listener.count == count, "ambiguous network denial")
        reachable()
        require(listener.count == count + 1, "sandbox connection observed")
        module.check_fixture(allowed)
        passed = True
    except Exception as failure:
        error = f"{type(failure).__name__}: {failure}"
    finally:
        if listener is not None:
            try:
                listener.close(end)
            except Exception as failure:
                passed = False
                error = f"listener cleanup: {failure}"
        if time.monotonic() > end:
            passed = False
            error = "suite deadline exceeded"
        if passed:
            try:
                require(end - time.monotonic() > 0.1, "no cleanup deadline budget")
                clean_fixture(module, root / "allowed", end)
            except Exception as failure:
                passed = False
                error = f"fixture cleanup: {failure}"
        if time.monotonic() > end:
            passed = False
            error = "suite deadline exceeded after cleanup"
    if passed:
        print("PASS: synthetic file/inherited/network cases only; no SDK qualification")
        return 0
    remaining = root if root is not None and root.exists() else None
    print(f"FAIL/unknown: {error}; remaining fixture root: {remaining}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
