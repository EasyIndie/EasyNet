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
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location("native_build", Path(__file__).parents[1] / "build.py")
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)


class BuildTests(unittest.TestCase):
    capture_records = {}
    def setUp(self):
        parent = "/private/tmp" if Path("/private/tmp").exists() else "/tmp"
        self.temp = tempfile.TemporaryDirectory(prefix="easynet-qb-test-", dir=parent)
        self.root = Path(self.temp.name).resolve()
        (self.root / "tmp").mkdir()
        self.records = self.capture_records[self._testMethodName] = []

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
        finally:
            self.records.extend(records[:max(0, 2 - len(self.records))])

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

    def binary(self, sectioned=False):
        executable = self.root / "EasyNetNativeLab"
        if sectioned:
            section1 = struct.pack("<16s16sQQ8I", b"__one", b"__TEXT", 0x1000001E0, 16, 480, 0, 0, 0, 0, 0, 0, 0)
            section2 = struct.pack("<16s16sQQ8I", b"__two", b"__TEXT", 0x1000001F0, 16, 496, 0, 0, 0, 0, 0, 0, 0)
            zero = struct.pack("<16s16sQQ8I", b"__zero", b"__BSS", 0x100001100, 64, 9999, 0, 0, 0, 1, 0, 0, 0)
            segment = (struct.pack("<II16sQQQQiiII", 0x19, 232, b"__TEXT", 0x100000000,
                                   4096, 0, 512, 7, 5, 2, 0) + section1 + section2 +
                       struct.pack("<II16sQQQQiiII", 0x19, 152, b"__BSS", 0x100001000,
                                   4096, 512, 0, 3, 3, 1, 0) + zero)
            entry_at, commands, total_size = 480, 432, 512
        else:
            segment = struct.pack("<II16sQQQQiiII", 0x19, 72, b"__TEXT", 0x100000000,
                                  4096, 0, 256, 7, 5, 0, 0)
            entry_at, commands, total_size = 200, 120, 256
        entry = struct.pack("<IIQQ", 0x80000028, 24, entry_at, 0)
        build = struct.pack("<6I", 0x32, 24, 1, 0xF0000, 0xF0500, 0)
        count = 4 if sectioned else 3
        data = struct.pack("<8I", 0xFEEDFACF, 0x100000C, 0, 2, count, commands, 0, 0) + segment + entry + build
        executable.write_bytes(data + bytes(total_size - len(data)))
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
        if value == "cleanup":
            rec = records[0]
            self.assertEqual((rec["primary_error"], rec["group_stage"], rec["group_errno"]),
                             ("overflow", "identity", "absent"))
            self.assertTrue(all(rec[key] for key in ("drained", "reaped", "fd_closed")))
        else:
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
        records = self.records
        self.reject("spawn", b.capture, [str(self.root / "absent")], self.root, {},
                    time.monotonic() + 10, 5, records)
        self.assertTrue(records[0]["fd_closed"])
        value, _ = self.fake("import os\nos.write(1, b'\\xff')\n")
        self.assertEqual(value, "identity")

    def test_artifact_valid_and_rejection_matrix(self):
        executable, plist = self.binary()
        valid = executable.read_bytes()
        self.assertEqual(b.artifact(executable, plist)["size"], len(valid))
        output = b.result()
        self.assertEqual((output["artifact_predicate"], output["artifact_build_mismatches"],
                          output["artifact_sdk_version"]), ("not-run", None, None))
        self.assertEqual(b.artifact(executable, plist, out=output),
                         {"sha256": b.digest(valid), "size": len(valid)})
        self.assertEqual(output["artifact_predicate"], "passed")
        self.assertEqual(output["artifact_build_mismatches"], dict.fromkeys(("platform", "minimum", "sdk", "length"), False))
        self.assertEqual(output["artifact_sdk_version"], {"major": 15, "minor": 5, "patch": 0})
        for encoded, version in ((0, (0, 0, 0)), (0xF0501, (15, 5, 1)),
                                 (0xFFFFFF, (255, 255, 255)), (0x1000000, None)):
            data = bytearray(valid)
            struct.pack_into("<I", data, 144, encoded)
            executable.write_bytes(data)
            self.reject("artifact", b.artifact, executable, plist, float("inf"), output)
            self.assertEqual(output["artifact_predicate"], "build-fields")
            self.assertEqual(output["artifact_build_mismatches"], {"platform": False, "minimum": False, "sdk": True, "length": False})
            self.assertEqual(output["artifact_sdk_version"], None if version is None else dict(zip(("major", "minor", "patch"), version)))
        valid_version = {"major": 15, "minor": 5, "patch": 1}
        for diagnostic, expected in ((valid_version, valid_version), (None, None), ("15.5.1", None),
                ({"major": 15, "minor": 5}, None), ({**valid_version, "extra": 0}, None),
                ({**valid_version, "major": True}, None), ({**valid_version, "minor": -1}, None),
                ({**valid_version, "major": 256}, None)):
            with contextlib.redirect_stdout(io.StringIO()) as stream:
                b.emit({"artifact_sdk_version": diagnostic, "padding": "x" * 16385})
            self.assertLessEqual(len(stream.getvalue().encode()), 16384)
            self.assertEqual(json.loads(stream.getvalue())["artifact_sdk_version"], expected)
        for offset, key, value in ((136, "platform", 2), (140, "minimum", 0), (144, "sdk", 0), (148, "length", 1)):
            data = bytearray(valid)
            struct.pack_into("<I", data, offset, value)
            executable.write_bytes(data)
            self.reject("artifact", b.artifact, executable, plist, float("inf"), output)
            self.assertEqual(output["artifact_build_mismatches"], {field: field == key for field in ("platform", "minimum", "sdk", "length")})
        data = bytearray(valid)
        for offset, value in ((20, 128), (132, 32), (148, 1), (152, 3), (156, 0)):
            struct.pack_into("<I", data, offset, value)
        executable.write_bytes(data)
        self.assertEqual(b.artifact(executable, plist)["sha256"], b.digest(data))
        variants = [(b"", "header-length"), (valid[:40], "header-fields"),
                    (b"\xca\xfe\xba\xbe" + valid[4:], "header-fields")]
        for offset, value in ((4, 0x1000007), (12, 1), (20, 16), (36, 7),
                              (36, 64), (136, 0xE0000), (140, 0xF0400), (144, 1),
                              (112, 9999), (80, 9999), (92, 1), (96, 1)):
            data = bytearray(valid)
            struct.pack_into("<I", data, offset, value)
            predicate = ("header-fields" if offset in (4, 12, 20) else
                         "command-length" if offset == 36 and value == 7 else
                         "segment-length" if offset == 36 else
                         "build-fields" if offset in (136, 140, 144) else
                         "entry-bounds" if offset == 112 else
                         "segment-bounds" if offset in (80, 96) else
                         "entry-bounds" if offset == 92 else "segment-bounds")
            variants.append((data, predicate))
        for data, predicate in variants:
            executable.write_bytes(data)
            output = {"artifact_sdk_version": {"major": 15, "minor": 5, "patch": 1}}
            self.reject("artifact", b.artifact, executable, plist, float("inf"), output)
            self.assertEqual(output["artifact_predicate"], predicate)
            if predicate in ("header-length", "header-fields", "command-length", "segment-length", "segment-bounds"):
                self.assertIsNone(output["artifact_sdk_version"])
        executable.write_bytes(valid)
        plist.write_bytes(b"malformed")
        output = {}
        self.reject("artifact", b.artifact, executable, plist, float("inf"), output)
        self.assertEqual(output["artifact_predicate"], "plist-read")
        plist.write_bytes(plistlib.dumps({}))
        output = {}
        self.reject("artifact", b.artifact, executable, plist, float("inf"), output)
        self.assertEqual(output["artifact_predicate"], "plist-content")
        plist.write_bytes(plistlib.dumps({"CFBundlePackageType": "APPL", "CFBundleExecutable": executable.name,
            "CFBundleIdentifier": "com.example.easynet.native-lab", "CFBundleName": "EasyNet Native Lab",
            "CFBundleVersion": "0.0.1", "CFBundleShortVersionString": "0.0.1",
            "LSMinimumSystemVersion": "15.0"}))
        sectioned, section_plist = self.binary(sectioned=True)
        section_output = {}
        section_valid = sectioned.read_bytes()
        self.assertEqual(b.artifact(sectioned, section_plist, out=section_output),
                         {"sha256": b.digest(section_valid), "size": len(section_valid)})
        self.assertEqual(section_output["artifact_predicate"], "passed")
        section_data = bytearray(sectioned.read_bytes())
        struct.pack_into("<Q", section_data, 136, 0x100001FFC)
        sectioned.write_bytes(section_data)
        section_output = {}
        self.reject("artifact", b.artifact, sectioned, section_plist, float("inf"), section_output)
        self.assertEqual(section_output["artifact_predicate"], "section-vm")
        struct.pack_into("<Q", section_data, 136, 0x1000001E0)
        struct.pack_into("<I", section_data, 152, 510)
        sectioned.write_bytes(section_data)
        section_output = {}
        self.reject("artifact", b.artifact, sectioned, section_plist, float("inf"), section_output)
        self.assertEqual(section_output["artifact_predicate"], "section-file")
        executable.unlink()
        executable.symlink_to(plist)
        output = {}
        self.reject("artifact", b.artifact, executable, plist, float("inf"), output)
        self.assertEqual(output["artifact_predicate"], "file-mode-bounds")

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
        ready = self.root / "owner-ready"
        os.mkfifo(fifo, 0o600)
        started = time.monotonic()
        # Independent live fixture owner holds its own group identity until fixed
        # cleanup command/watchdog. It never signals a remembered/reaped PID.
        program = f"""import os,signal,time
if os.fork():
 os._exit(0)
signal.signal(signal.SIGTERM, signal.SIG_IGN)
control=os.open({str(fifo)!r},os.O_RDONLY|os.O_NONBLOCK)
with open({str(ready)!r},"x") as marker:
 marker.write("ready")
end=time.monotonic()+6
while time.monotonic()<end:
 if os.read(control,16)==b'cleanup':
  os.killpg(os.getpgrp(),signal.SIGKILL)
 time.sleep(0.02)
os.killpg(os.getpgrp(),signal.SIGKILL)
"""
        try:
            value, records = self.fake(program)
            self.assertIn(value, ("timeout", "cleanup"))
            self.assertTrue(records[0]["reaped"] and records[0]["fd_closed"])
            if value == "cleanup":
                self.assertEqual(records[0]["primary_error"], "timeout")
                self.assertEqual((records[0]["group_stage"], records[0]["group_errno"]), ("identity", "absent"))
            else:
                self.assertTrue(records[0]["drained"])
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
            self.assertEqual(ready.read_text(), "ready")
            while True:
                self.assertLess(time.monotonic(), started + 7, "fixture exit deadline")
                try:
                    fd = os.open(fifo, os.O_WRONLY | os.O_NONBLOCK)
                except OSError as exc:
                    self.assertEqual(exc.errno, errno.ENXIO)
                    break
                os.close(fd)
                self.assertLess(time.monotonic(), started + 7, "fixture reader persisted")
                time.sleep(0.02)
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
        target = developer / "swift-frontend"
        target.write_bytes(b"vendor-entry")
        compiler.symlink_to(target)
        sdk = developer / "MacOSX15.5.sdk"
        sdk.mkdir()
        alias = developer / "MacOSX.sdk"
        alias.symlink_to(sdk)
        def fake_run(argv):
            if "--find" in argv:
                return str(compiler)
            if "--show-sdk-path" in argv:
                return str(alias)
            self.assertEqual(argv[0], str(compiler))
            if "--version" in argv:
                return "Apple Swift version 6.1.2"
            return " ".join(b.REQUIRED)
        with patch.multiple(b, DEV=developer, SWIFT=compiler, SDK=sdk):
            info, found = b.identity(fake_run, b.BASE)
            self.assertEqual(info["size"], len(b"vendor-entry"))
            self.assertEqual((info["path"], info["hash_path"]), (str(compiler), str(target)))
            self.assertEqual(found, sdk)
            alias.unlink()
            alias.symlink_to(self.root)
            self.reject("identity", b.identity, fake_run, b.BASE)
            alias.unlink()
            sdk.rmdir()
            alias.mkdir()
            sdk.symlink_to(alias)
            _, found = b.identity(fake_run, b.BASE)
            self.assertEqual(found, sdk)
            self.assertNotEqual(found, alias)
            self.assertEqual(found.resolve(strict=True), alias)
            sdk.unlink()
            sdk.symlink_to(self.root)
            self.reject("identity", b.identity, fake_run, b.BASE)
        self.reject("timeout", b.entry_hash, target, time.monotonic() - 1)
        self.reject("timeout", b.sources, self.root, None, time.monotonic() - 1)
        value, records = self.fake("print('ok')\n", budget=4)
        self.assertEqual(value, "timeout")
        self.assertFalse(records[0]["reaped"])

    def test_signal_failure_does_not_skip_direct_child_reap(self):
        streams = []
        for _ in range(2):
            reader, writer = os.pipe()
            os.close(writer)
            streams.append(os.fdopen(reader, "rb"))
        proc = Mock(pid=123, returncode=None, stdout=streams[0], stderr=streams[1])
        proc.wait.side_effect = [b.subprocess.TimeoutExpired("fixture", 1), 0]
        records = self.records
        with patch.object(b.subprocess, "Popen", return_value=proc), \
             patch.object(b.os, "getpgid", return_value=123), \
             patch.object(b.os, "killpg", side_effect=PermissionError):
            self.reject("cleanup", b.capture, ["inert mock"], self.root, {},
                        time.monotonic() + 10, 5, records)
        self.assertEqual(proc.wait.call_count, 2)
        self.assertEqual(records[0]["primary_error"], "timeout")
        self.assertEqual((records[0]["group_stage"], records[0]["group_errno"]), ("term", "other"))
        self.assertTrue(records[0]["reaped"] and records[0]["fd_closed"])
        self.assertTrue(all(stream.closed for stream in streams))

    def test_driver_jobs_parser_and_grant(self):
        logical, canonical = "/qualified SDK", "/canonical SDK"
        expected = {"tool": "frontend", "target": "expected", "sdk": "qualified-logical",
                    "platform_version_present": True}
        prefix = '"/vendor tools/swift-frontend" -target arm64-apple-macosx15.0 -sdk "/qualified SDK" '
        for form in ("-platform_version macos 15.0 15.5", "-Wl,-platform_version,macos,15.0,15.5",
                     "-Xlinker -platform_version -Xlinker macos -Xlinker 15.0 -Xlinker 15.5"):
            self.assertEqual(b.driver_jobs("\n" + prefix + form + "\n", logical, canonical), [expected])
        for tool, flag in (("clang", "-isysroot"), ("ld", "-syslibroot")):
            jobs = b.driver_jobs(f'{tool} --target=other {flag} "{canonical}"', logical, canonical)
            self.assertEqual(jobs, [{"tool": tool, "target": "other", "sdk": "qualified-canonical",
                                     "platform_version_present": False}])
        jobs = b.driver_jobs("unknown --target arm64-apple-macosx15.0 -sdk secret-path -Xlinker harmless", logical, canonical)
        self.assertEqual(jobs[0], {"tool": "other", "target": "expected", "sdk": "other",
                                  "platform_version_present": False})
        self.assertNotIn("secret", json.dumps(jobs))
        self.assertEqual(b.driver_jobs("ld irrelevant-sdk-text", logical, canonical)[0]["sdk"], "absent")
        for path, expected in ((logical, "qualified-logical"), (canonical, "qualified-canonical")):
            self.assertEqual(b.driver_jobs(f'clang --sysroot "{path}"', logical, canonical), [{"tool": "clang",
                "target": "absent", "sdk": expected, "platform_version_present": False}])
        metadata = ("-target-sdk-version", "-target-sdk-name", "-target-variant-sdk-version")
        for extra in [f'{flag} {value}' for flag in metadata for value in ("15.5", '"15.5"')] + [
                '-target-sdk-version 15.5 -target-sdk-name macosx15.5 -target-variant-sdk-version 18.5']:
            plan = f'swift-frontend -target arm64-apple-macosx15.0 -sdk "{logical}" {extra}'
            self.assertEqual(b.driver_jobs(plan, logical, canonical), [{"tool": "frontend", "target": "expected",
                "sdk": "qualified-logical", "platform_version_present": False}])
        malformed = ("", "ld 'broken", "ld \0secret", "ld \ud800", "ld @secret", "ld -filelist secret",
            "ld -Xlinker", "ld -Xfrontend", 'ld -Xlinker ""', 'ld -Xfrontend ""',
            "ld -target", 'ld --target=""', "ld -sdk -next", "ld -sdk=x", "ld -targetx x",
            "ld --target=", "ld -isysroot=/secret", "ld -syslibrootx x", "ld -platform_version=x",
            "ld -target x --target x", "ld -target x --target=y", "ld -sdk x -isysroot x",
            "ld -sdk x -syslibroot y", "ld -platform_version macos 15", "ld -platform_version macos -x 15",
            "ld -Wl,-platform_version,macos,15", "ld -Wl,-platform_version,macos,15,15,extra",
            "ld -Wl,-platform_version,,15,15", "ld -Xlinker -platform_version -Xlinker macos",
            "ld -Xlinker -platform_version macos 15 15", "ld -Wl,-target,x", "ld -Xfrontend -sdk",
            "ld -Xlinker -sdk", "ld -Wp,-syslibroot,x", "ld -Wl,-platform_versionx,macos,15,15",
            "ld -platform_version macos 15 15 -Wl,-platform_version,macos,15,15",
            "\n".join(["ld"] * 9), "ld " + "x " * 512, "ld " + "x" * 4097,
            "ld " + "é" * 2049, "ld " + "x" * 65536)
        metadata_bad = tuple(f'swift-frontend {flag}{suffix}' for flag in metadata for suffix in
            ("", ' ""', " -sdk x", " @x", f" 15 {flag} 15", "x 15", "=15")) + tuple(
            f'{tool} {prefix}{flag}{suffix}' for flag in metadata for tool, prefix, suffix in
            (("swift-frontend", "-Xfrontend ", " 15"), ("swift-frontend", "-Wl,", ",15"),
             ("clang", "", " 15"), ("ld", "", " 15")))
        sysroot_bad = ("clang --sysroot", 'clang --sysroot ""', "clang --sysroot -sdk x", "clang --sysroot @x",
            "clang --sysroot=x", "clang --sysrootx x", "clang -Xlinker --sysroot x", "clang -Wl,--sysroot,x") + tuple(
            f'clang {first} x {second} x' for flag in ("--sysroot", "-sdk", "-isysroot", "-syslibroot")
            for first, second in (("--sysroot", flag), (flag, "--sysroot")))
        for text in malformed + metadata_bad + sysroot_bad:
            with self.subTest(case=text):
                self.reject("plan-format", b.driver_jobs, text, logical, canonical)
        for args in ((None, logical, canonical), ("ld", None, canonical), ("ld", logical, b"sdk")):
            self.reject("plan-format", b.driver_jobs, *args)
        self.assertEqual(len(b.driver_jobs("\n".join(["ld"] * 8), logical, canonical)), 8)
        self.assertEqual(b.driver_jobs("ld " + "x " * 511, logical, canonical)[0]["target"], "absent")
        self.assertEqual(b.driver_jobs("ld " + "é" * 2048, logical, canonical)[0]["sdk"], "absent")
        binding = self.manifest()
        bad_bindings = [(None, "source-mismatch"), ([], "source-mismatch")] + [
            (dict(binding, grant=grant, qualification=qualification, python_verified=True), "identity")
            for grant, qualification in (("one-driver-jobs-only", None), ("one-driver-jobs-only", "wrong"),
                ("one-compile-only", "sdk-driver-jobs-hosted19-v1"), (None, "sdk-driver-jobs-hosted19-v1"))]
        for invalid, code in bad_bindings:
            with patch.object(b, "capture") as capture, patch.object(b.Path, "mkdir") as mkdir:
                out = b.build(self.root, invalid)
            self.assertEqual((out["error"], out["cleanup"], out["commands"]), (code, "not-created", []))
            self.assertIsNone(out["driver_jobs"])
            capture.assert_not_called()
            mkdir.assert_not_called()
        binding.update(grant="one-driver-jobs-only", qualification="sdk-driver-jobs-hosted19-v1", python_verified=True)
        for mutate in (False, True):
            def fake_capture(argv, root, env, whole, budget, records, cancel):
                self.assertTrue(root.is_relative_to(self.root))
                records.append({"reaped": True, "drained": True, "fd_closed": True})
                if budget == 120:
                    self.assertEqual(argv[-1], "-driver-print-jobs")
                    if mutate:
                        (root / "src/Host.swift").write_bytes(b"changed fixed fixture")
                    return f'ld -sdk "{self.root}"'
                return {"-productVersion": b.BASE["os"], "-buildVersion": b.BASE["build"],
                        "-m": b.BASE["arch"], "-version": b.BASE["xcode"],
                        "--show-sdk-version": b.BASE["sdk_version"]}[argv[-1]]
            def owned_path(value):
                return self.root if value == "/private/tmp" else Path(value)
            with patch.object(b, "Path", side_effect=owned_path), \
                 patch.object(b, "identity", return_value=({"path": "inert compiler"}, self.root)), \
                 patch.object(b, "capture", side_effect=fake_capture) as capture, \
                 patch.object(b, "artifact") as artifact, patch.object(b.subprocess, "Popen") as spawn, \
                 patch.dict(os.environ, ImageOS=b.BASE["image_os"], ImageVersion=b.BASE["image_version"]):
                out = b.build(self.root, binding)
            self.assertEqual(capture.call_count, 6)
            artifact.assert_not_called()
            spawn.assert_not_called()
            self.assertEqual((out["phase"], out["artifact"], out["artifact_predicate"]), ("driver-jobs", None, "not-run"))
            self.assertFalse(out["candidate-executed"])
            self.assertEqual(tuple(out[key] for key in ("gui", "engine", "ne")), ("not-run",) * 3)
            owned = self.root / ("easynet-qb-build-" + out["run_token"])
            if mutate:
                self.assertEqual((out["result"], out["error"], out["cleanup"]), ("failed", "cleanup", "retained"))
                self.assertIsNone(out["driver_jobs"])
                self.assertEqual((owned / "src/Host.swift").read_bytes(), b"changed fixed fixture")
                info = owned.stat()
                b.cleanup(owned, info.st_uid, info.st_ino, b.inventory(owned, b.TOPS))
            else:
                self.assertEqual((out["result"], out["error"], out["cleanup"]), ("planned", "none", "removed"))
                self.assertEqual(out["driver_jobs"], [{"tool": "ld", "target": "absent", "sdk": "qualified-logical",
                                                       "platform_version_present": False}])
            self.assertFalse(owned.exists())

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
    fields = {"command", "exit", "deadline", "bytes", "drained", "fd_closed", "reaped", "cancelled",
              "group_observation", "ownership", "primary_error", "group_stage", "group_errno"}
    names = {
        'test_driver_jobs_parser_and_grant', 'test_source_identity_and_tampering', 'test_unfrozen_and_extra_manifest',
        'test_links_modes_and_bounds', 'test_environment_is_constructed',
        'test_changed_baseline_rejected_without_locator', 'test_escaped_locator',
        'test_bounded_output_success_and_nonzero', 'test_flood_timeout_and_kill_reap',
        'test_inherited_pipes_are_drained_before_success', 'test_spawn_failure_and_malformed_text',
        'test_artifact_valid_and_rejection_matrix', 'test_inventory_and_cleanup_reject_unexpected_or_replaced',
        'test_owned_early_exit_hung_writer_and_cancellation', 'test_term_output_and_wait_ownership_guard',
        'test_canonical_inventory_adoption_and_multidir_cleanup', 'test_sdk_alias_stream_hash_and_whole_deadline',
        'test_signal_failure_does_not_skip_direct_child_reap', 'test_missing_binding_is_finite_and_no_build',
    }
    failed = sorted({case._testMethodName for case, _ in result.failures + result.errors} & names)
    output = {"schema": 1, "tests": result.testsRun, "failures": len(result.failures),
              "errors": len(result.errors), "skipped": len(result.skipped),
              "result": "passed" if result.wasSuccessful() else "failed",
              "fixture_cleanup": "passed" if result.wasSuccessful() else "unknown",
              "failed_cases": failed, "captures": {name: [{key: value for key, value in rec.items() if key in fields}
                  for rec in BuildTests.capture_records.get(name, [])[:2]] for name in failed}}
    encoded = json.dumps(output, sort_keys=True, separators=(",", ":"))
    if len(encoded.encode()) > 16384:
        encoded = json.dumps({"schema": 1, "result": "failed", "error": "overflow"})
    print(encoded)
    sys.exit(0 if result.wasSuccessful() else 1)
