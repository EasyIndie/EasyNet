"""Private synthetic fixtures; source review and exact execution grant required."""
import importlib.util
import io
import json
import os
import signal
from pathlib import Path
import sys
import threading
import time
import unittest
from unittest.mock import Mock, patch
SOURCE = Path(__file__).resolve().parents[2] / "poc/client-framework/hosted-ci/observe.py"
CASES = {
    "normal": "print('15.7.9')",
    "stderr": "import sys;sys.stderr.write('synthetic');print('15.7.9')",
    "nonzero": "raise SystemExit(3)",
    "timeout": "import time;time.sleep(30)",
    "overflow": "import os;os.write(1,b'x'*5000)",
    "cancel": "import time;time.sleep(30)",
    "descendant": "import subprocess,sys;subprocess.Popen([sys.executable,'-I','-c','import time;time.sleep(30)']);print('15.7.9')",
    "environment": "import os;print('clean' if os.getenv('SYNTHETIC_TOKEN') is None and os.getenv('HOME') is None else 'bad')",
}
class ObserverTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("hosted_observer", SOURCE)
        cls.observer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.observer)

    def setUp(self):
        self.observer.CANCELLED = False

    def case(self, name):
        # Internal synthetic cases only; production entry has no argv interface.
        return self.observer.capture((sys.executable, "-I", "-c", CASES[name]), time.monotonic() + 0.4)

    def testParserNegativeCases(self):
        cases = (("os-version", b"", "missing"), ("os-version", b"26.0", "os-major"),
                 ("architecture", b"x86_64", "architecture"), ("sdk", b"15.x", "format"),
                 ("os-build", b"24G830 extra", "format"), ("xcode", b"Xcode 16.4", "format"),
                 ("xcode", b"Xcode 16.4\nBuild version 16F6\nextra", "format"),
                 ("sdk", b"\xff", "format"), ("unknown", b"15.5", "schema"))
        for label, raw, expected in cases:
            with self.subTest(label=label, raw=raw):
                self.assertEqual(self.observer.parse(label, raw), (None, expected))
        self.assertEqual(self.observer.parse("xcode", b"Xcode 16.4\nBuild version 16F6\n"),
                         ({"version": "16.4", "build": "16F6"}, "none"))

    def testReportRejectsMalformedProviderSchemaCleanup(self):
        provider = {"ImageOS": "macos15", "ImageVersion": "synthetic"}
        for data, records, error in (({}, [], "none"), ({"ImageOS": "x\nsecret"}, [], "provider"),
                                     (provider, [{}], "none"), (provider, [], "invented")):
            report = json.loads(self.observer.report(data, records, error))
            self.assertEqual((report["result"], report["error"]), ("refused", "schema"))
        record = dict(command="os-version", result="observed", error="none", value="15.7.9",
                      cleanup=dict(child="reaped", group="unknown", drain=True, fds=True))
        result = json.loads(self.observer.report(provider, [record], "cancel"))
        self.assertEqual(result["error"], "schema")

    def testRealSyntheticLifecycle(self):
        for name, expected in (("normal", "none"), ("stderr", "stderr"), ("nonzero", "nonzero"),
                               ("timeout", "timeout"), ("overflow", "overflow"), ("descendant", "timeout")):
            raw, error, proof = self.case(name)
            group = "not-requested" if name in {"normal", "stderr", "nonzero"} else "signalled"
            self.assertEqual(proof, dict(child="reaped", group=group, drain=True, fds=True))
            with self.subTest(case=name):
                self.assertEqual(error, expected)
                self.assertLessEqual(len(raw), 4096)
        # Descendant inherited group/FDs reclaimed; no arbitrary descendant proof.

    def testRealSyntheticCancellation(self):
        previous = signal.signal(signal.SIGTERM, self.observer.cancel)
        timer = threading.Timer(0.05, lambda: os.kill(os.getpid(), signal.SIGTERM))
        timer.start()
        try:
            _, error, proof = self.case("cancel")
            self.assertEqual(error, "cancel")
            self.assertEqual(proof, dict(child="reaped", group="signalled", drain=True, fds=True))
        finally:
            timer.cancel()
            timer.join(timeout=1)
            signal.signal(signal.SIGTERM, previous)

    def testCleanupFaultsDoNotSkipLaterAttempts(self):
        for failure in ("group", "reap", "drain", "close"):
            child = Mock(pid=123, stdout=Mock(), stderr=Mock())
            child.wait.return_value = 0
            selector = Mock()
            selector.select.side_effect = PermissionError()  # Abnormal branch, not natural EOF.
            selector.get_map.return_value = {}
            if failure == "reap":
                child.wait.side_effect = TimeoutError()
            if failure == "drain":
                selector.select.side_effect = PermissionError()
                selector.get_map.return_value = {1: "synthetic"}
            if failure == "close":
                child.stdout.close.side_effect = PermissionError()
            group_error = PermissionError() if failure == "group" else None
            with patch.object(self.observer.subprocess, "Popen", return_value=child), \
                 patch.object(self.observer.selectors, "DefaultSelector", return_value=selector), \
                 patch.object(self.observer.os, "set_blocking"), \
                 patch.object(self.observer.os, "killpg", side_effect=group_error) as kill:
                _, error, proof = self.observer.capture(("synthetic",), time.monotonic() + 0.4)
            with self.subTest(failure=failure):
                self.assertEqual(error, failure)
                self.assertEqual(kill.call_count, 2)
                child.wait.assert_called_once()
                selector.close.assert_called_once()
                child.stdout.close.assert_called_once()
                child.stderr.close.assert_called_once()
                if failure == "close":
                    self.assertFalse(proof["fds"])
                if failure == "reap":
                    self.assertEqual(proof["child"], "unknown")

    def testChildEnvironmentAndProviderRefusal(self):
        self.assertEqual(self.observer.ENV, {"PATH": "/usr/bin:/bin", "LANG": "C", "LC_ALL": "C"})
        with patch.dict(os.environ, {"SYNTHETIC_TOKEN": "private-fixture"}):
            raw, error, proof = self.case("environment")
            self.assertEqual((raw, error, proof["child"]), (b"clean\n", "none", "reaped"))
        with patch.dict(os.environ, {"ImageOS": "bad\nvalue", "ImageVersion": "synthetic"}), \
             patch.object(self.observer, "capture") as capture, patch("builtins.print") as output:
            self.assertEqual(self.observer.main(), 1)
            capture.assert_not_called()
            value = json.loads(output.call_args.args[0])
            self.assertEqual(value["error"], "provider")
            self.assertEqual(value["descendants"], "not-proven")
            self.assertLessEqual(len(output.call_args.args[0].encode()), 4096)
    def testSignalOwnershipRefusalAndCompleteReport(self):
        with patch.object(self.observer.signal, "getsignal", return_value=signal.SIG_IGN), \
             patch.object(self.observer.subprocess, "Popen") as spawn:
            _, error, proof = self.case("normal")
            self.assertEqual(error, "unsupported")
            spawn.assert_not_called()
            self.assertEqual(proof["child"], "not-started")
        provider = {"ImageOS": "macos15", "ImageVersion": "synthetic"}
        fields = ["15.7.9", "24G830", "arm64", {"version": "16.4", "build": "16F6"}, "15.5"]
        records = [dict(command=label, result="observed", error="none", value=field,
                        cleanup=dict(child="reaped", group="not-requested", drain=True, fds=True))
                   for (label, _), field in zip(self.observer.COMMANDS, fields)]
        self.assertEqual(json.loads(self.observer.report(provider, records))["result"], "metadata-observed")
        self.assertEqual(json.loads(self.observer.report(provider, records, "cancel"))["error"], "cancel")


    def testNaturalWaitOwnershipTransitions(self):
        for outcome, expected, signals in (("timeout", "timeout", 2), ("cancel", "cancel", 0), ("unknown", "reap", 0)):
            child = Mock(pid=123, stdout=Mock(), stderr=Mock())
            selector = Mock()
            selector.select.return_value = []
            selector.get_map.return_value = {}
            clock = [0.0]
            def wait(**_):
                if outcome == "unknown":
                    raise PermissionError()
                if outcome == "cancel":
                    self.observer.CANCELLED = True
                elif clock[0] == 0:
                    clock[0] = 0.2
                    raise self.observer.subprocess.TimeoutExpired("synthetic", 0.05)
                return 0
            child.wait.side_effect = wait
            self.observer.CANCELLED = False
            with patch.object(self.observer.subprocess, "Popen", return_value=child), patch.object(self.observer.selectors, "DefaultSelector", return_value=selector), patch.object(self.observer.os, "set_blocking"), patch.object(self.observer.time, "monotonic", side_effect=lambda: clock[0]), patch.object(self.observer.os, "killpg") as kill:
                _, error, proof = self.observer.capture(("synthetic",), 0.1)
            self.assertEqual((error, kill.call_count), (expected, signals))
            self.assertEqual(proof["child"], "unknown" if outcome == "unknown" else "reaped")


if __name__ == "__main__":
    try:
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(ObserverTests)
        result = unittest.TextTestRunner(stream=io.StringIO()).run(suite)
        print(json.dumps(dict(schema=1, result="passed" if result.wasSuccessful() else "failed", tests=result.testsRun, failures=len(result.failures), errors=len(result.errors))))
        status = 0 if result.wasSuccessful() else 1
    except BaseException:
        print('{"schema":1,"result":"refused","tests":0,"failures":0,"errors":1}')
        status = 1
    raise SystemExit(status)
