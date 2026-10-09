"""Source-only fixtures: independent R must approve imports and execution first."""
import importlib.util
import json
import os
import select
import signal
import sys
import tempfile
import time
import unittest
from pathlib import Path

class DriverRefusals(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = Path(__file__).resolve().parents[2] / "poc/client-framework/window-admission/driver.py"
        spec = importlib.util.spec_from_file_location("window_driver", source)
        cls.driver = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.driver)

    def testMissingMalformedIncompleteBinding(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "binding.json"
            with self.assertRaises(OSError):
                self.driver.binding(str(path), Path(directory))
            for content in ("{", "{}", '{"schema":1,"accepted":false}'):
                path.write_text(content)
                with self.assertRaises((ValueError, self.driver.Refusal)):
                    self.driver.binding(str(path), Path(directory))

    def testSymlinkAndUnownedManifestRefused(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "target").write_text("synthetic")
            (root / "link").symlink_to(root / "target")
            with self.assertRaises(self.driver.Refusal):
                self.driver.checked_path(str(root / "link"), "file")
            with self.assertRaises(self.driver.Refusal):
                owned = self.driver.OwnedRoot(root)
                try: self.driver.cleanup(owned, time.monotonic() + 1)
                finally: owned.close()
            self.assertTrue((root / "target").exists())

    def testRetainedRootReplacementRefused(self):
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory)
            root = parent / "root"; root.mkdir(mode=0o700)
            owned = self.driver.OwnedRoot(root)
            try:
                root.rename(parent / "retained")
                root.symlink_to(parent / "retained", target_is_directory=True)
                with self.assertRaises(self.driver.Refusal):
                    self.driver.cleanup(owned, time.monotonic() + 1)
                self.assertTrue((parent / "retained").is_dir())
            finally: owned.close()

    def testUnacceptedEffectsUnknownVersionAndHashMismatch(self):
        checkout = Path(__file__).resolve().parents[2]
        value = {key: "reviewed-synthetic" for key in (
            "image_os", "image_version", "os_build", "developer", "compiler", "sdk",
            "xcode_version", "swift_version", "compiler_hash", "xcodebuild_hash", "sdk_settings_hash")}
        value.update(schema=1, accepted=True, one_guest=True, architecture="arm64",
                     runner_selector="macos-15", provenance="reviewed-installed-vendor-toolchain",
                     effects={key: True for key in self.driver.EFFECTS}, manifest=self.driver.MANIFEST,
                     source_hashes={key: self.driver.digest(checkout / key) for key in self.driver.SOURCES})
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "binding.json"
            for key, replacement in (("accepted", False), ("effects", {}),
                                     ("swift_version", "unknown"), ("source_hashes", {})):
                fixture = dict(value); fixture[key] = replacement
                path.write_text(json.dumps(fixture))
                with self.assertRaises(self.driver.Refusal):
                    self.driver.binding(str(path), checkout)

    def testParentEOFReclaimsGroup(self):
        directory = tempfile.mkdtemp()
        reaped = False
        pid = None
        result_r = None
        deadline = time.monotonic() + 5
        try:
            env = {"PATH": "/usr/bin:/bin", "LANG": "C", "TMPDIR": directory}
            self.driver.clean_environment(env)
            control_r, control_w = os.pipe(); result_r, result_w = os.pipe()
            pid = os.fork()
            if pid == 0:
                os.close(control_w); os.close(result_r)
                self.driver.guardian([sys.executable, "-I", "-B", "-c", "import time;time.sleep(20)"],
                    env,
                    directory, 3, control_r, result_w)
            os.close(control_r); os.close(result_w); os.close(control_w)
            data = bytearray()
            eof = False
            while time.monotonic() < deadline:
                if select.select([result_r], [], [], 0.02)[0]:
                    block = os.read(result_r, 4096)
                    if not block: eof = True; break
                    data.extend(block)
                    self.assertLessEqual(len(data), 49152)
            self.assertTrue(eof, "EOF observation exceeded independent deadline")
            self.driver.reap_before(pid, deadline)
            reaped = True
            report = json.loads(data)
            self.assertEqual(report["reason"], "parent-eof")
            self.assertTrue(report["direct_reaped"] and report["group_absent"])
            self.assertTrue(report["fds_closed"])
        finally:
            if result_r is not None: os.close(result_r)
            if pid is not None and not reaped:
                # Retained direct PID only; request guardian cleanup, never kill it.
                try: os.kill(pid, signal.SIGTERM)
                except ProcessLookupError: pass
                self.driver.reap_before(pid, time.monotonic() + 1)
                reaped = True
            if reaped: Path(directory).rmdir()

    def testEmptyOwnedSignalDoesNotSkipOtherFailures(self):
        def gone(*_): raise ProcessLookupError()
        def denied(*_): raise PermissionError()
        self.driver.signal_owned(gone, 0, signal.SIGKILL)
        with self.assertRaises(PermissionError):
            self.driver.signal_owned(denied, 0, signal.SIGKILL)

    def testOverflowTimeoutAndReap(self):
        # Owned fixture subprocesses; these are not window qualification.
        with tempfile.TemporaryDirectory() as directory:
            env = {"PATH": "/usr/bin:/bin", "LANG": "C", "TMPDIR": directory}
            for source in ("import os;os.write(1,b'x'*20000)",
                           "import time;time.sleep(20)"):
                with self.assertRaises(self.driver.Refusal):
                    self.driver.bounded([sys.executable, "-I", "-B", "-c", source], env, directory, 3)
            self.assertEqual(self.driver.bounded(
                [sys.executable, "-I", "-B", "-c", "print('synthetic')"], env, directory, 3), "synthetic")


if __name__ == "__main__":
    unittest.main()
