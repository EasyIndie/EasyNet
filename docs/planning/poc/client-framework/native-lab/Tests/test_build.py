"""Review before execution. Every subprocess is an inert owned Python fixture."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import signal
import errno
import struct
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("native_build", Path(__file__).parents[1] / "build.py")
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)


class BuildTests(unittest.TestCase):
    def setUp(self):
        parent = "/private/tmp" if Path("/private/tmp").exists() else "/tmp"
        self.temp = tempfile.TemporaryDirectory(prefix="easynet-qb-test-", dir=parent)
        self.root = Path(self.temp.name).resolve()
        (self.root / "tmp").mkdir()

    def tearDown(self):
        self.temp.cleanup()
        self.assertFalse(self.root.exists())

    def reject(self, code, call, *args):
        with self.assertRaises(b.Reject) as raised:
            call(*args)
        self.assertEqual(raised.exception.code, code)

    def fake(self, program, budget=5):
        source = self.root / "fixture.py"
        source.write_text(program)
        records = []
        try:
            value = b.capture([sys.executable, "-I", "-B", str(source)], self.root,
                              b.environment(self.root), time.monotonic() + 10, budget, records)
            return value, records
        except b.Reject as exc:
            return exc.code, records

    def manifest(self):
        entries = {}
        for name in b.FILES:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"inert source\n")
            path.chmod(0o644)
            entries[name] = {"type": "regular", "mode": 0o644,
                             "sha256": b.digest(path.read_bytes()), "size": path.stat().st_size}
        contract = self.root / "docs/planning/poc/client-framework/native-build-contract.md"
        contract.write_bytes(b"accepted fixture contract")
        return {"schema": 1, "feature": "1" * 40, "checkout": "1" * 40,
                "workflow": entries[".github/workflows/g0-client-native-build.yml"]["sha256"],
                "contract": b.digest(contract.read_bytes()), "sources": entries,
                "manifest": b.digest(json.dumps(entries, sort_keys=True, separators=(",", ":")).encode())}

    def binary(self):
        executable = self.root / "EasyNetNativeLab"
        segment = struct.pack("<II16sQQQQiiII", 0x19, 72, b"__TEXT", 0x100000000,
                              4096, 0, 256, 7, 5, 0, 0)
        entry = struct.pack("<IIQQ", 0x80000028, 24, 200, 0)
        build = struct.pack("<6I", 0x32, 24, 1, 0xF0000, 0xF0500, 0)
        data = struct.pack("<8I", 0xFEEDFACF, 0x100000C, 0, 2, 3, 120, 0, 0) + segment + entry + build
        executable.write_bytes(data + bytes(256 - len(data)))
        executable.chmod(0o700)
        plist = self.root / "Info.plist"
        plist.write_bytes(plistlib.dumps({"CFBundlePackageType": "APPL", "CFBundleExecutable": executable.name,
            "CFBundleIdentifier": "com.example.easynet.native-lab", "CFBundleName": "EasyNet Native Lab",
            "CFBundleVersion": "0.0.1", "CFBundleShortVersionString": "0.0.1",
            "LSMinimumSystemVersion": "15.0"}))
        plist.chmod(0o600)
        return executable, plist

    def test_source_identity_and_tampering(self):
        binding = self.manifest()
        self.assertEqual(set(b.sources(self.root, binding)), set(b.FILES))
        binding["checkout"] = "2" * 40
        self.reject("source-mismatch", b.sources, self.root, binding)
        binding["checkout"] = binding["feature"]
        (self.root / next(iter(b.FILES))).write_bytes(b"changed")
        self.reject("source-mismatch", b.sources, self.root, binding)

    def test_unfrozen_and_extra_manifest(self):
        self.reject("source-mismatch", b.sources, self.root, None)
        binding = self.manifest()
        binding["sources"]["extra"] = {}
        self.reject("source-mismatch", b.sources, self.root, binding)

    def test_links_modes_and_bounds(self):
        target = self.root / "data"
        target.write_bytes(b"abc")
        link = self.root / "link"
        link.symlink_to(target)
        self.reject("source-mismatch", b.regular, link, 8)
        self.reject("source-mismatch", b.regular, target, 2)
        target.chmod(0o600)
        self.reject("source-mismatch", b.regular, target, 8, 0o644)

    def test_environment_is_constructed(self):
        with patch.dict(os.environ, {"DYLD_INSERT_LIBRARIES": "bad", "SSH_AUTH_SOCK": "bad",
                                     "HTTPS_PROXY": "bad", "HOME": "unchanged"}):
            env = b.environment(self.root)
        self.assertEqual(env["HOME"], "unchanged")
        self.assertTrue(set(env) <= {"PATH", "LC_ALL", "DEVELOPER_DIR", "TMPDIR", "HOME", "CODEX_HOME"})

    def test_changed_baseline_rejected_without_locator(self):
        observed = dict(b.BASE, os="26.0")
        def forbidden(_):
            self.fail("locator ran before baseline rejection")
        self.reject("identity", b.identity, forbidden, observed)

    def test_escaped_locator(self):
        self.reject("identity", b.identity, lambda _: "/usr/bin/false", dict(b.BASE))

    def test_bounded_output_success_and_nonzero(self):
        value, records = self.fake("import sys\nprint('ok')\nsys.stderr.write('detail')\n")
        self.assertEqual(value, "ok")
        self.assertEqual(records[0]["bytes"], [3, 6])
        self.assertTrue(all(records[0][key] for key in ("drained", "fd_closed", "reaped")))
        self.assertEqual(records[0]["group_observation"], "not-requested")
        value, records = self.fake("raise SystemExit(7)\n")
        self.assertEqual(value, "tool-unavailable")
        self.assertEqual(records[0]["exit"], 7)

    def test_flood_timeout_and_kill_reap(self):
        value, records = self.fake("import os\nos.write(1, b'x' * 131072)\n")
        self.assertEqual(value, "overflow")
        self.assertGreater(records[0]["bytes"][0], 65536)
        value, records = self.fake("import signal,time\nsignal.signal(signal.SIGTERM, signal.SIG_IGN)\ntime.sleep(30)\n")
        self.assertEqual(value, "timeout")
        self.assertTrue(records[0]["reaped"] and records[0]["fd_closed"])
        self.assertEqual(records[0]["exit"], -signal.SIGKILL)

    def test_inherited_pipes_are_drained_before_success(self):
        value, records = self.fake("import os,time\npid=os.fork()\nif pid == 0:\n time.sleep(0.2)\n os.write(1,b'child\\n')\n os._exit(0)\nos._exit(0)\n")
        self.assertEqual(value, "child")
        self.assertTrue(records[0]["drained"] and records[0]["reaped"])

    def test_spawn_failure_and_malformed_text(self):
        records = []
        self.reject("spawn", b.capture, [str(self.root / "absent")], self.root, {},
                    time.monotonic() + 10, 5, records)
        self.assertTrue(records[0]["fd_closed"])
        value, _ = self.fake("import os\nos.write(1, b'\\xff')\n")
        self.assertEqual(value, "identity")

    def test_artifact_valid_and_rejection_matrix(self):
        executable, plist = self.binary()
        valid = executable.read_bytes()
        self.assertEqual(b.artifact(executable, plist)["size"], 256)
        variants = [b"", valid[:40], b"\xca\xfe\xba\xbe" + valid[4:]]
        for offset, value in ((4, 0x1000007), (12, 1), (20, 16), (36, 7),
                              (36, 64), (136, 0xE0000), (140, 0xF0400), (144, 1),
                              (112, 9999), (80, 9999), (92, 1), (96, 1)):
            data = bytearray(valid)
            struct.pack_into("<I", data, offset, value)
            variants.append(data)
        for data in variants:
            executable.write_bytes(data)
            self.reject("artifact", b.artifact, executable, plist)
        executable.write_bytes(valid)
        plist.write_bytes(b"malformed")
        self.reject("artifact", b.artifact, executable, plist)
        executable.unlink()
        executable.symlink_to(plist)
        self.reject("artifact", b.artifact, executable, plist)

    def test_inventory_and_cleanup_reject_unexpected_or_replaced(self):
        owned = self.root / "owned"
        owned.mkdir(mode=0o700)
        child = owned / "file"
        child.write_bytes(b"owned")
        info = owned.stat()
        expected = b.inventory(owned, ["file"])
        (owned / "extra").write_bytes(b"unexpected")
        self.reject("cleanup", b.cleanup, owned, info.st_uid, info.st_ino, expected)
        (owned / "extra").unlink()
        self.reject("cleanup", b.cleanup, owned, info.st_uid, info.st_ino + 1, expected)
        child.unlink()
        child.symlink_to(self.root / "outside")
        self.reject("cleanup", b.inventory, owned, ["file"])
        child.unlink()
        child.write_bytes(b"owned")
        b.cleanup(owned, info.st_uid, info.st_ino, b.inventory(owned, ["file"]))
        self.assertFalse(owned.exists())

    def test_owned_early_exit_hung_writer_and_cancellation(self):
        fifo = self.root / "owner-control"
        os.mkfifo(fifo, 0o600)
        # Independent live fixture owner holds its own group identity until fixed
        # cleanup command/watchdog. It never signals a remembered/reaped PID.
        program = f"""import os,signal,time
if os.fork():
 os._exit(0)
signal.signal(signal.SIGTERM, signal.SIG_IGN)
control=os.open({str(fifo)!r},os.O_RDONLY|os.O_NONBLOCK)
end=time.monotonic()+6
while time.monotonic()<end:
 if os.read(control,16)==b'cleanup':
  os.killpg(os.getpgrp(),signal.SIGKILL)
 time.sleep(0.02)
os.killpg(os.getpgrp(),signal.SIGKILL)
"""
        try:
            value, records = self.fake(program)
            self.assertEqual(value, "timeout")
            self.assertTrue(records[0]["drained"] and records[0]["reaped"])
            self.assertEqual(records[0]["group_observation"], "signals-issued-unproven")
        finally:
            try:
                fd = os.open(fifo, os.O_WRONLY | os.O_NONBLOCK)
            except OSError as exc:
                if exc.errno != errno.ENXIO:
                    raise
            else:
                try:
                    os.write(fd, b"cleanup")
                finally:
                    os.close(fd)
        value, records = self.fake("import os,signal,time\nos.kill(os.getppid(),signal.SIGTERM)\ntime.sleep(30)\n")
        self.assertEqual(value, "cancelled")
        self.assertTrue(records[0]["cancelled"] and records[0]["reaped"])

    def test_term_output_and_wait_ownership_guard(self):
        value, records = self.fake("import os,signal,time\ndef term(*_):\n os.write(2,b'term-output')\n raise SystemExit(0)\nsignal.signal(signal.SIGTERM,term)\ntime.sleep(30)\n")
        self.assertEqual(value, "timeout")
        self.assertGreaterEqual(records[0]["bytes"][1], len(b"term-output"))
        self.assertTrue(records[0]["drained"])
        with patch.object(signal, "getsignal", return_value=signal.SIG_IGN):
            self.reject("cleanup", b.capture, ["never-spawn"], self.root, {},
                        time.monotonic() + 10, 5, [])

    def test_canonical_inventory_adoption_and_multidir_cleanup(self):
        owned = self.root / "tree"
        owned.mkdir()
        for top in reversed(b.TOPS):
            (owned / top).mkdir()
        (owned / "src/fixed").write_bytes(b"fixed")
        fixed = b.inventory(owned, b.TOPS)
        (owned / "module-cache/generated").write_bytes(b"cache")
        adopted = b.adoption(owned, fixed, time.monotonic() + 5)
        self.assertEqual(adopted, b.inventory(owned, list(reversed(b.TOPS))))
        (owned / "result/unexpected").write_bytes(b"bad")
        self.reject("cleanup", b.adoption, owned, adopted, time.monotonic() + 5)
        (owned / "result/unexpected").unlink()
        info = owned.stat()
        b.cleanup(owned, info.st_uid, info.st_ino, adopted)
        self.assertFalse(owned.exists())

    def test_sdk_alias_stream_hash_and_whole_deadline(self):
        developer = self.root / "developer"
        developer.mkdir()
        compiler = developer / "swiftc"
        compiler.write_bytes(b"vendor-entry")
        sdk = developer / "MacOSX15.5.sdk"
        sdk.mkdir()
        alias = developer / "MacOSX.sdk"
        alias.symlink_to(sdk)
        def fake_run(argv):
            if "--find" in argv:
                return str(compiler)
            if "--show-sdk-path" in argv:
                return str(alias)
            if "--version" in argv:
                return "Apple Swift version 6.1.2"
            return " ".join(b.REQUIRED)
        with patch.multiple(b, DEV=developer, SWIFT=compiler, SDK=sdk):
            info, found = b.identity(fake_run, b.BASE)
            self.assertEqual(info["size"], len(b"vendor-entry"))
            self.assertEqual(found, sdk)
            alias.unlink()
            alias.symlink_to(self.root)
            self.reject("identity", b.identity, fake_run, b.BASE)
        self.reject("timeout", b.entry_hash, compiler, time.monotonic() - 1)
        self.reject("timeout", b.sources, self.root, None, time.monotonic() - 1)
        value, records = self.fake("print('ok')\n", budget=4)
        self.assertEqual(value, "timeout")
        self.assertFalse(records[0]["reaped"])

    def test_missing_binding_is_finite_and_no_build(self):
        with patch.object(b, "build", side_effect=AssertionError("build must not run")):
            with contextlib.redirect_stdout(io.StringIO()) as stream:
                b.main()
        output = json.loads(stream.getvalue())
        self.assertEqual(output["result"], "rejected")
        self.assertFalse(output["candidate-executed"])
        self.assertLess(len(stream.getvalue()), 16384)


if __name__ == "__main__":
    class BoundedOutput(io.StringIO):
        def write(self, value):
            super().write(value[:max(0, 4096 - self.tell())])
            return len(value)
    captured = BoundedOutput()
    with contextlib.redirect_stdout(captured), contextlib.redirect_stderr(captured):
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(BuildTests)
        result = unittest.TextTestRunner(stream=captured).run(suite)
    print(json.dumps({"schema": 1, "tests": result.testsRun,
                      "failures": len(result.failures), "errors": len(result.errors),
                      "skipped": len(result.skipped),
                      "result": "passed" if result.wasSuccessful() else "failed",
                      "fixture_cleanup": "passed" if result.wasSuccessful() else "unknown"}))
    sys.exit(0 if result.wasSuccessful() else 1)
