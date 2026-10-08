"""Controlled main/cleanup faults; every fixture and loader operation is fake."""
import importlib.util
from pathlib import Path
import stat
import unittest
from unittest.mock import MagicMock, Mock, patch


def load():
    spec = importlib.util.spec_from_file_location("mapping_diag", Path(__file__).parent / "mapping_diag.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class MainTests(unittest.TestCase):
    def exercise(self, fault=None, setup=0.5, after_sequence=6, passed=True):
        module = load()
        phase = {"name": "setup"}
        times = {"setup": 0, "ready": setup, "finished": after_sequence}
        source, root, allowed, decoy = (MagicMock() for _ in range(4))
        source.absolute.return_value = source
        source.parent.__truediv__.return_value = source
        root.__truediv__.side_effect = lambda name: allowed if name == "allowed" else decoy
        fixture = Mock(_live=set())
        def freeze(path):
            phase["name"] = "ready"
            if fault == "manifest":
                raise ValueError("fake manifest")
        fixture.freeze_fixture.side_effect = freeze
        def sequence(*args):
            phase["name"] = "finished"
            return passed
        sequence_mock = Mock(side_effect=sequence)
        clean = Mock()
        if fault == "cleanup":
            clean.side_effect = OSError("fake cleanup")
        if fault == "finish-deadline":
            clean.side_effect = RuntimeError("cleanup deadline exhausted")
        mkdtemp = Mock(return_value="synthetic-root")
        if fault == "allocation":
            mkdtemp.side_effect = OSError("fake allocation")
        fake_open = Mock(return_value=42)
        if fault == "setup":
            fake_open.side_effect = OSError("fake seed creation")
        stream = MagicMock()
        stream.__enter__.return_value = stream
        with patch.object(module, "Path", side_effect=lambda p: root if p == "synthetic-root" else source), \
                patch.object(module.sys, "argv", ["fixed-driver"]), \
                patch.object(module.sys, "platform", "darwin"), \
                patch.object(module.os, "getuid", return_value=123), \
                patch.object(module.os, "chmod") as chmod, \
                patch.object(module.os, "open", fake_open), \
                patch.object(module.os, "fdopen", return_value=stream), \
                patch.object(module.os, "fchmod") as fchmod, \
                patch.object(module.tempfile, "mkdtemp", mkdtemp), \
                patch.object(module.uuid, "uuid4", return_value=Mock(hex="synthetic-nonce")), \
                patch.object(module.importlib.util, "spec_from_file_location", return_value=Mock()) as spec, \
                patch.object(module.importlib.util, "module_from_spec", return_value=fixture), \
                patch.object(module.time, "monotonic", side_effect=lambda: times[phase["name"]]), \
                patch.object(module, "sequence", sequence_mock), \
                patch.object(module, "clean_fixture", clean), patch("builtins.print") as output:
            code = module.main()
        return code, output, sequence_mock, clean, root, allowed, decoy, fixture, chmod, fchmod, spec

    def test_allocation_setup_manifest_failures_never_cleanup_or_launch(self):
        for fault in ("allocation", "setup", "manifest"):
            with self.subTest(fault=fault):
                code, output, sequence, clean, *rest = self.exercise(fault)
                self.assertEqual(code, 1)
                sequence.assert_not_called()
                clean.assert_not_called()
                summary = "no fixture allocated" if fault == "allocation" else "pre-cleanup fixture retained"
                self.assertIn(summary, output.call_args.args[0])
                for path in rest[:3]:
                    path.rmdir.assert_not_called()

    def test_setup_limit_and_sequence_failure_retain_whole_fixture(self):
        for options in ({"setup": 4}, {"setup": 5}, {"passed": False}):
            with self.subTest(options=options):
                code, output, sequence, clean, root, allowed, decoy, *_ = self.exercise(**options)
                self.assertEqual(code, 1)
                clean.assert_not_called()
                self.assertIn("pre-cleanup fixture retained", output.call_args.args[0])
                for path in (root, allowed, decoy):
                    path.rmdir.assert_not_called()
                if "setup" in options:
                    sequence.assert_not_called()
                else:
                    sequence.assert_called_once()

    def test_success_combined_finish_and_absolute_budgets(self):
        code, _, sequence, clean, root, allowed, decoy, fixture, chmod, fchmod, spec = self.exercise(setup=3)
        self.assertEqual(code, 0)
        self.assertEqual(sequence.call_args.args[4], 12)
        clean.assert_called_once_with(fixture, allowed, 7)
        self.assertEqual(chmod.call_args_list[0].args, (root, 0o700))
        self.assertEqual(fchmod.call_count, 2)
        fixture.freeze_fixture.assert_called_once_with(allowed)
        spec.return_value.loader.exec_module.assert_called_once_with(fixture)
        for options in ({"after_sequence": 12}, {"after_sequence": 13},
                        {"fault": "cleanup"}, {"fault": "finish-deadline", "setup": 3}):
            code, output, sequence, clean, *_ = self.exercise(**options)
            self.assertEqual(code, 1)
            if "fault" in options:
                self.assertIn("remaining fixture state unknown", output.call_args.args[0])
                clean.assert_called_once()
                if options["fault"] == "finish-deadline":
                    self.assertEqual(clean.call_args.args[2], 7)
            else:
                self.assertIn("pre-cleanup fixture retained", output.call_args.args[0])
                clean.assert_not_called()


class CleanupTests(unittest.TestCase):
    def exercise(self, fault=None):
        module = load()
        root, allowed, decoy, first, second = (MagicMock() for _ in range(5))
        allowed.parent = root
        root.__truediv__.return_value = decoy
        files, directories = (first, second), (allowed, decoy, root)
        entries = {p: (1, n, 123, stat.S_IFREG | 0o600) for n, p in enumerate(files)}
        entries.update({p: (1, n + 2, 123, stat.S_IFDIR | 0o700) for n, p in enumerate(directories)})
        fixture = Mock(_live={42} if fault == "live" else set())
        fixture.check_fixture.return_value = entries
        state = {"expired": fault == "initial-deadline"}
        if fault == "manifest":
            fixture.check_fixture.side_effect = ValueError("fake invalid manifest")
        def identity(path, directory=False):
            if (fault == "file-identity" and path is first) or (fault == "dir-identity" and path is allowed):
                return (9, 9, 9, 9)
            return entries[path]
        fixture._identity.side_effect = identity
        def remove_first():
            if fault == "unlink":
                raise OSError("fake unlink")
            if fault == "post-unlink-deadline":
                state["expired"] = True
        first.unlink.side_effect = remove_first
        def remove_allowed():
            if fault == "rmdir":
                raise OSError("fake rmdir")
        allowed.rmdir.side_effect = remove_allowed
        if fault == "final-deadline":
            root.rmdir.side_effect = lambda: state.update(expired=True)
        with patch.object(module.time, "monotonic", side_effect=lambda: 12 if state["expired"] else 0):
            try:
                module.clean_fixture(fixture, allowed, 12)
                error = None
            except Exception as caught:
                error = caught
        return module, error, fixture, files, directories

    def test_pre_removal_guards(self):
        for fault in ("live", "manifest", "file-identity", "initial-deadline"):
            with self.subTest(fault=fault):
                module, error, fixture, files, directories = self.exercise(fault)
                self.assertIsNotNone(error)
                for path in files:
                    path.unlink.assert_not_called()
                for path in directories:
                    path.rmdir.assert_not_called()
                self.assertIn("remaining fixture state unknown", module.failure_summary(True, True))
                if fault in ("live", "initial-deadline"):
                    fixture.check_fixture.assert_not_called()

    def test_final_deadline_failure_after_all_removals_is_unknown(self):
        module, error, _, files, directories = self.exercise("final-deadline")
        self.assertIsNotNone(error)
        for path in files:
            path.unlink.assert_called_once_with()
        for path in directories:
            path.rmdir.assert_called_once_with()
        self.assertIn("remaining fixture state unknown", module.failure_summary(True, True))

    def test_partial_cleanup_stops_at_first_failure(self):
        for fault in ("unlink", "post-unlink-deadline", "dir-identity", "rmdir"):
            with self.subTest(fault=fault):
                module, error, _, files, directories = self.exercise(fault)
                self.assertIsNotNone(error)
                files[0].unlink.assert_called_once_with()
                if fault in ("unlink", "post-unlink-deadline"):
                    files[1].unlink.assert_not_called()
                    directories[0].rmdir.assert_not_called()
                else:
                    files[1].unlink.assert_called_once_with()
                    if fault == "dir-identity":
                        directories[0].rmdir.assert_not_called()
                    else:
                        directories[0].rmdir.assert_called_once_with()
                for path in directories[1:]:
                    path.rmdir.assert_not_called()
                self.assertIn("remaining fixture state unknown", module.failure_summary(True, True))


if __name__ == "__main__":
    unittest.main()
