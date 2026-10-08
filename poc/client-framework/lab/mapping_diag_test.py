"""Source/fake contracts only; modeled selectors are not runtime mmap evidence."""
import ast
import hashlib
import importlib.util
from pathlib import Path
import re
import stat
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, Mock, patch

BASE = Path(__file__).parent
ORIGINAL = "b554c29d574b6c1852f7facbdbd8e4fe10af7864ec64637a3191055e2e8e3c82"
MAPPING = "1dfc6055110b29f06ccd2026eb230433cd5ca6da9be2354b2c43fb88efba0595"
CASES = ("direct-eof", "sandbox-eof", "allowed-read", "denied-read")
ROOT = Path("/private/tmp/easynet-g0-06-isolate-fake")
DENIAL = b"cat: " + str(ROOT / "decoy/seed").encode() + b": Operation not permitted\n"


def load(name):
    spec = importlib.util.spec_from_file_location(name, BASE / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def result(case):
    out = b"allowed-nonce" if case == "allowed-read" else b""
    err = DENIAL if case == "denied-read" else b""
    return dict(returncode=1 if err else 0, timed_out=False, reaped=True, elapsed_s=0.05,
                stdout=out, stderr=err, stdout_count=len(out), stderr_count=len(err),
                phase="leader-wait", primary_class="none", primary_errno=None,
                cleanup_class="none", cleanup_errno=None, waitid_exit_observed=True,
                group_check="sole-zombie", owned_pid=42, leader_wait_completed=True,
                signals=[], errors=[], stdout_eof=True, stderr_eof=True,
                stdout_closed=True, stderr_closed=True, helper_wait_completed=True)


class ProfileTests(unittest.TestCase):
    def test_exact_single_operation_delta_and_modeled_membership(self):
        old = (BASE / "fixture.sb").read_bytes()
        new = (BASE / "mapping-fixture.sb").read_bytes()
        self.assertEqual(hashlib.sha256(old).hexdigest(), ORIGINAL)
        self.assertEqual(hashlib.sha256(new).hexdigest(), MAPPING)
        clause = (b'(allow file-map-executable (literal "/bin/sh") (literal "/bin/cat")\n'
                  b'  (literal "/usr/bin/touch") (literal "/usr/bin/curl")\n'
                  b'  (subpath "/usr/lib") (subpath "/System/Library/dyld"))\n')
        self.assertEqual(new, old + clause)
        selectors = re.findall(rb'\((literal|subpath) "([^"]+)"\)', clause)
        self.assertEqual(selectors, [(b"literal", p) for p in
                         (b"/bin/sh", b"/bin/cat", b"/usr/bin/touch", b"/usr/bin/curl")]
                         + [(b"subpath", b"/usr/lib"), (b"subpath", b"/System/Library/dyld")])
        # Lexical membership model only: no SBPL interpreter or mmap launch.
        def modeled(path):
            return any(path == target or (kind == b"subpath" and path.startswith(target + b"/"))
                       for kind, target in selectors)
        for _, target in selectors:
            self.assertTrue(modeled(target))
        for path in (b"/usr/lib/fixture", b"/System/Library/dyld/fixture"):
            self.assertTrue(modeled(path))
        for path in (str(ROOT).encode(), str(ROOT / "allowed/seed").encode(),
                     str(ROOT / "decoy/seed").encode(), b"/outside", b"/bin/cat-extra",
                     b"/usr/library/fixture", b"/System/Library/dyld-extra/fixture",
                     b"/System/Library/fixture", b"/Users/synthetic/home"):
            self.assertFalse(modeled(path))

    def test_old_public_entries_still_select_original_guards(self):
        tree = ast.parse((BASE / "isolate.py").read_text())
        for node in tree.body:
            if isinstance(node, ast.FunctionDef) and node.name in ("run_probe", "run_startup_control"):
                calls = [n for n in ast.walk(node) if isinstance(n, ast.Call)
                         and isinstance(n.func, ast.Name) and n.func.id == "_probe_guards"]
                self.assertEqual(len(calls), 1)
                self.assertEqual(len(calls[0].args), 2)
                self.assertFalse(calls[0].keywords)


class ProbeTests(unittest.TestCase):
    def setUp(self):
        self.module = load("isolate")

    def test_exact_argv_all_cases_guards_even_direct(self):
        profile = BASE / "mapping-fixture.sb"
        with patch.object(self.module, "_probe_guards", return_value=(ROOT, profile)) as guards, \
                patch.object(self.module, "_execute", return_value={}) as execute:
            for case in CASES:
                self.module.run_mapping_probe(profile, ROOT / "allowed", case)
                guards.assert_called_with(profile, ROOT / "allowed", _mapping=True)
                argv = ["/bin/cat"]
                if case in ("allowed-read", "denied-read"):
                    argv += [str(ROOT / ("allowed" if case == "allowed-read" else "decoy") / "seed")]
                if case != "direct-eof":
                    argv = ["/usr/bin/sandbox-exec", "-f", str(profile), "-D",
                            "ALLOWED_ROOT=" + str(ROOT / "allowed"), *argv]
                execute.assert_called_with(argv, case, 2)
            for case in (False, [], "allowed-write", "/bin/cat", "DIRECT-EOF"):
                with self.assertRaises(ValueError):
                    self.module.run_mapping_probe(profile, ROOT / "allowed", case)
            self.assertEqual(execute.call_count, 4)

    def test_full_variant_guard_rejects_wrong_path_hash_mode_and_live(self):
        profile = MagicMock()
        profile.resolve.return_value = profile
        directory = MagicMock()
        directory.__truediv__.return_value = profile
        source = MagicMock()
        source.absolute.return_value.parent = directory
        profile.lstat.return_value = SimpleNamespace(st_mode=stat.S_IFREG | 0o644,
                                                     st_uid=123, st_nlink=1)
        profile.read_bytes.return_value = (BASE / "mapping-fixture.sb").read_bytes()
        with patch.object(self.module, "Path", side_effect=lambda p: source if p == self.module.__file__ else p), \
                patch.object(self.module.sys, "platform", "darwin"), \
                patch.object(self.module.os, "getuid", return_value=123), \
                patch.object(self.module, "_root", return_value=ROOT), \
                patch.object(self.module, "check_fixture") as manifest:
            self.module._probe_guards(profile, ROOT / "allowed", True)
            directory.__truediv__.assert_called_with("mapping-fixture.sb")
            manifest.assert_called_once_with(ROOT / "allowed")
            with self.assertRaisesRegex(ValueError, "hash mismatch"):
                self.module._probe_guards(profile, ROOT / "allowed")
            profile.read_bytes.return_value = b"changed profile"
            with self.assertRaisesRegex(ValueError, "hash mismatch"):
                self.module._probe_guards(profile, ROOT / "allowed", True)
            profile.read_bytes.return_value = (BASE / "mapping-fixture.sb").read_bytes()
            directory.__truediv__.return_value = Mock()
            with self.assertRaisesRegex(ValueError, "canonical path"):
                self.module._probe_guards(profile, ROOT / "allowed", True)
            directory.__truediv__.return_value = profile
            for mode, links, uid in ((stat.S_IFREG | 0o666, 1, 123),
                                     (stat.S_IFLNK | 0o644, 1, 123),
                                     (stat.S_IFREG | 0o644, 2, 123),
                                     (stat.S_IFREG | 0o644, 1, 456)):
                profile.lstat.return_value = SimpleNamespace(st_mode=mode, st_uid=uid, st_nlink=links)
                with self.assertRaisesRegex(ValueError, "ownership"):
                    self.module._probe_guards(profile, ROOT / "allowed", True)
            profile.resolve.return_value = Mock()
            with self.assertRaisesRegex(ValueError, "canonical path"):
                self.module._probe_guards(profile, ROOT / "allowed", True)
            with self.assertRaises(ValueError):
                self.module._probe_guards(profile, ROOT / "allowed", 1)
            self.module._live.add(42)
            with self.assertRaisesRegex(ValueError, "not verified reaped"):
                self.module._probe_guards(profile, ROOT / "allowed", True)
            self.module._live.clear()


class DriverTests(unittest.TestCase):
    def setUp(self):
        self.module = load("mapping_diag")

    def attempt(self, fail_case=None, change=None):
        calls, records = [], []
        def probe(case, budget):
            calls.append((case, budget))
            value = result(case)
            if case == fail_case:
                if change is None:
                    raise OSError("fake")
                value.update(change)
            return value
        passed = self.module.sequence(probe, b"allowed-nonce", b"decoy-nonce",
                                      ROOT / "decoy/seed", 12, lambda: 0, records.append)
        return passed, calls, records

    def test_order_once_exact_denial_redacted(self):
        passed, calls, records = self.attempt()
        self.assertTrue(passed)
        self.assertEqual(calls, [(case, 2) for case in CASES])
        self.assertEqual([r["case"] for r in records], list("ABCD"))
        self.assertTrue(all(r["expected_match"] for r in records))
        self.assertNotIn("nonce", repr(records))
        self.assertNotIn(str(ROOT), repr(records))

    def test_faults_stop_first_failure_in_every_case(self):
        faults = dict(returncode=-6, timed_out=True, reaped=False, elapsed_s=1,
                      stdout=b"decoy-nonce", stderr=b"generic denial", stdout_count=8193,
                      stderr_count=8193, primary_class="OSError", primary_errno=1,
                      cleanup_class="OSError", cleanup_errno=1, waitid_exit_observed=False,
                      group_check="unknown", leader_wait_completed=False, signals=["term"],
                      owned_pid=0,
                      errors=[{}], stdout_eof=False, stderr_eof=False, stdout_closed=False,
                      stderr_closed=False, helper_wait_completed=False)
        for case in CASES:
            for field, value in faults.items():
                with self.subTest(case=case, field=field):
                    passed, calls, records = self.attempt(case, {field: value})
                    self.assertFalse(passed)
                    self.assertEqual(len(calls), CASES.index(case) + 1)
                    self.assertEqual(records[-1]["outcome"], "unknown")
            self.assertFalse(self.attempt(case)[0])
        for change in ({"returncode": 0}, {"returncode": 2}, {"stderr": b""},
                       {"stderr": DENIAL + b"decoy-nonce"}, {"stdout": b"wrong"}):
            self.assertFalse(self.attempt("denied-read", change)[0])

    def test_deadline_and_cleanup_state(self):
        probe = Mock()
        self.assertFalse(self.module.sequence(probe, b"a", b"d", ROOT / "decoy/seed",
                                             0.5, lambda: 0, Mock()))
        probe.assert_not_called()
        self.assertIn("pre-cleanup fixture retained", self.module.failure_summary(True, False))
        self.assertIn("remaining fixture state unknown", self.module.failure_summary(True, True))
        tree = ast.parse((BASE / "mapping_diag.py").read_text())
        self.assertFalse(any(isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
                             and n.func.attr in ("rmtree", "walk", "kill") for n in ast.walk(tree)))


if __name__ == "__main__":
    unittest.main()
