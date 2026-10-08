"""Fake-only contracts; native execution requires a separate reviewed binding."""
import importlib.util
from pathlib import Path
import stat
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, Mock, patch


def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).parent / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def result(stdout=b""):
    return dict(returncode=0, timed_out=False, reaped=True, elapsed_s=0.05,
                stdout=stdout, stderr=b"", stdout_count=len(stdout), stderr_count=0,
                phase="leader-wait", primary_class="none", primary_errno=None,
                cleanup_class="none", cleanup_errno=None, waitid_exit_observed=True,
                group_check="sole-zombie", owned_pid=42, leader_wait_completed=True,
                signals=[], errors=[], stdout_eof=True, stderr_eof=True,
                stdout_closed=True, stderr_closed=True, helper_wait_completed=True)


class SequenceTests(unittest.TestCase):
    def setUp(self):
        self.module = load("startup_diag")

    def run_fake(self, broken=None, fail_at="A", raises=False):
        calls, records = [], []

        def invoke(label, budget):
            calls.append((label, budget))
            if label == fail_at and raises:
                raise OSError("fake failure")
            return broken if label == fail_at and broken is not None else result(
                b"synthetic" if label == "C" else b"")

        passed = self.module.sequence(
            lambda mode, budget: invoke("B" if mode else "A", budget),
            lambda budget: invoke("C", budget), b"synthetic", 10, lambda: 0,
            records.append)
        return passed, calls, records

    def test_fixed_order_budgets_and_redacted_output(self):
        passed, calls, records = self.run_fake()
        self.assertTrue(passed)
        self.assertEqual(calls, [("A", 2), ("B", 2), ("C", 2)])
        self.assertEqual([r["case"] for r in records], ["A", "B", "C"])
        self.assertTrue(all(r["expected_match"] for r in records))
        self.assertTrue(all("stdout" not in r and "stderr" not in r for r in records))

    def test_lifecycle_and_operation_failures_stop_next(self):
        faults = dict(returncode=-6, stdout=b"wrong", stdout_count=1, stderr_count=1,
                      reaped=False, timed_out=True, leader_wait_completed=False,
                      helper_wait_completed=False, waitid_exit_observed=False,
                      stdout_eof=False, stderr_eof=False, stdout_closed=False,
                      stderr_closed=False, group_check="unknown", elapsed_s=1,
                      signals=["signal-term"], errors=[{"phase": "metadata"}],
                      primary_class="OSError", cleanup_class="OSError")
        for label in ("A", "B", "C"):
            for field, value in faults.items():
                with self.subTest(label=label, field=field):
                    bad = result(b"synthetic" if label == "C" else b"")
                    bad[field] = value
                    passed, calls, records = self.run_fake(bad, label)
                    self.assertFalse(passed)
                    self.assertEqual([c[0] for c in calls], list("ABC")[:"ABC".index(label) + 1])
                    self.assertEqual(records[-1]["outcome"], "unknown")

    def test_exception_stops_next(self):
        for label in ("A", "B", "C"):
            passed, calls, records = self.run_fake(fail_at=label, raises=True)
            self.assertFalse(passed)
            self.assertEqual(len(calls), "ABC".index(label) + 1)
            self.assertEqual(records[-1], dict(case=label, outcome="unknown", expected_match=False))

    def test_absolute_deadline_prevents_launch_and_next(self):
        callback = Mock(return_value=result())
        self.assertFalse(self.module.sequence(callback, callback, b"", 0.5,
                                             lambda: 0, lambda record: None))
        callback.assert_not_called()
        ticks = iter((0, 11))
        self.assertFalse(self.module.sequence(callback, callback, b"", 10,
                                             lambda: next(ticks), lambda record: None))
        callback.assert_called_once_with(False, 2)


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.module = load("startup_diag")
        self.allowed, self.decoy, self.root = (MagicMock() for _ in range(3))
        self.allowed.parent = self.root
        self.root.__truediv__.return_value = self.decoy
        self.first, self.second = MagicMock(), MagicMock()
        self.entries = {self.first: (1, 1, 123, stat.S_IFREG | 0o600),
                        self.second: (1, 2, 123, stat.S_IFREG | 0o600)}
        for n, directory in enumerate((self.allowed, self.decoy, self.root), 3):
            self.entries[directory] = (1, n, 123, stat.S_IFDIR | 0o700)
        self.fixture = Mock(_live=set())
        self.fixture.check_fixture.return_value = self.entries
        self.fixture._identity.side_effect = lambda path, directory=False: self.entries[path]

    def test_fixed_reporting_states(self):
        self.assertEqual(self.module.failure_summary(False, False),
                         "FAIL/unknown: no fixture allocated; no further launch")
        self.assertEqual(self.module.failure_summary(True, False),
                         "FAIL/unknown: pre-cleanup fixture retained; no further launch")
        self.assertEqual(self.module.failure_summary(True, True),
                         "FAIL/unknown: cleanup started; remaining fixture state unknown")

    def test_partial_cleanup_failure_stops_remaining_removals(self):
        self.second.unlink.side_effect = OSError("fake unlink failure")
        with patch.object(self.module.time, "monotonic", return_value=0):
            with self.assertRaisesRegex(OSError, "fake unlink failure"):
                self.module.clean_fixture(self.fixture, self.allowed, 10)
        self.first.unlink.assert_called_once_with()
        self.second.unlink.assert_called_once_with()
        for directory in (self.allowed, self.decoy, self.root):
            directory.rmdir.assert_not_called()

    def test_final_deadline_failure_after_root_removal(self):
        with patch.object(self.module.time, "monotonic", side_effect=[0] * 11 + [11]):
            with self.assertRaisesRegex(RuntimeError, "final deadline exhausted"):
                self.module.clean_fixture(self.fixture, self.allowed, 10)
        self.root.rmdir.assert_called_once_with()
        self.assertIn("remaining fixture state unknown", self.module.failure_summary(True, True))


class ControlTests(unittest.TestCase):
    def setUp(self):
        self.module = load("isolate")
        self.root = Path("/private/tmp/easynet-g0-06-isolate-fake")
        self.profile = MagicMock()
        self.profile.__str__.return_value = "/fixed/fixture.sb"
        self.profile.resolve.return_value = self.profile
        self.profile.lstat.return_value = SimpleNamespace(st_mode=stat.S_IFREG | 0o644,
                                                         st_uid=123, st_nlink=1)
        source = MagicMock()
        source.absolute.return_value.parent.__truediv__.return_value = self.profile
        patches = [patch.object(self.module.sys, "platform", "darwin"),
                   patch.object(self.module.os, "getuid", return_value=123),
                   patch.object(self.module, "Path", side_effect=[self.profile, source] * 20),
                   patch.object(self.module, "_root", return_value=self.root),
                   patch.object(self.module, "check_fixture"),
                   patch.object(self.module, "_live", set()),
                   patch.object(self.module.hashlib, "sha256"),
                   patch.object(self.module, "_execute", return_value="fake record")]
        mocks = [self.enterContext(p) for p in patches]
        self.root_guard, self.fixture, self.digest, self.execute = mocks[3], mocks[4], mocks[6], mocks[7]
        self.digest.return_value.hexdigest.return_value = self.module.PROFILE_SHA256

    def run_control(self, mode):
        return self.module.run_startup_control("profile", "allowed", mode, 1.5)

    def test_exact_fixed_argv_and_shared_guards(self):
        for mode in (False, True):
            self.assertEqual(self.run_control(mode), "fake record")
            argv = ["/bin/cat"]
            if mode:
                argv = ["/usr/bin/sandbox-exec", "-f", "/fixed/fixture.sb", "-D",
                        "ALLOWED_ROOT=" + str(self.root / "allowed"), "/bin/cat"]
            self.execute.assert_called_with(argv, "sandbox-eof" if mode else "direct-eof", 1.5)
        self.assertEqual(self.fixture.call_count, 2)
        self.assertEqual(self.profile.read_bytes.call_count, 2)

    def test_strict_bool_rejection(self):
        for mode in (0, 1, "false", None, []):
            with self.assertRaisesRegex(ValueError, "must be bool"):
                self.run_control(mode)
        self.root_guard.assert_not_called()
        self.execute.assert_not_called()

    def test_guard_failures_block_both_modes(self):
        failures = (("platform", "unprivileged"), ("uid", "unprivileged"),
                    ("root", "canonical"), ("live", "previous child"),
                    ("fixture", "fixture changed"), ("profile", "canonical"),
                    ("owner", "ownership"), ("hash", "hash mismatch"))
        for mode in (False, True):
            for fault, message in failures:
                with self.subTest(mode=mode, fault=fault):
                    target, name, value = {
                        "platform": (self.module.sys, "platform", "linux"),
                        "uid": (self.module.os, "getuid", Mock(return_value=0)),
                        "root": (self.module, "_root", Mock(side_effect=ValueError("canonical"))),
                        "live": (self.module, "_live", {42}),
                        "fixture": (self.module, "check_fixture", Mock(side_effect=ValueError("fixture changed"))),
                        "profile": (self.profile, "resolve", Mock(return_value="alias")),
                        "owner": (self.profile, "lstat", Mock(return_value=SimpleNamespace(st_mode=stat.S_IFREG | 0o666, st_uid=123, st_nlink=1))),
                        "hash": (self.digest.return_value, "hexdigest", Mock(return_value="changed"))}[fault]
                    with patch.object(target, name, value), self.assertRaisesRegex(ValueError, message):
                        self.run_control(mode)
        self.execute.assert_not_called()

    def test_environment_remains_fixed(self):
        with patch.object(self.module.os, "environ", {"HOME": "fake-home", "CODEX_HOME": "fake-codex",
                                                     "DYLD_INSERT_LIBRARIES": "untrusted"}):
            self.assertEqual(self.module._environment(), {"PATH": "/usr/bin:/bin", "LC_ALL": "C",
                                                          "HOME": "fake-home", "CODEX_HOME": "fake-codex"})


if __name__ == "__main__":
    unittest.main()
