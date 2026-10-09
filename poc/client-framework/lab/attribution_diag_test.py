"""Fixed driver integration with clocks, modules and all environment faked."""
import importlib.util
import hashlib
import json
from pathlib import Path
import types
import unittest
from contextlib import ExitStack
from unittest.mock import Mock, patch


def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


d, r, mapping = load('attribution_diag'), load('attribution_record'), load('mapping_diag')


def result(stdout=b'', code=0):
    value = dict.fromkeys(('reaped', 'waitid_exit_observed', 'leader_wait_completed',
                          'helper_wait_completed', 'stdout_eof', 'stderr_eof',
                          'stdout_closed', 'stderr_closed'), True)
    value.update(timed_out=False, returncode=code, elapsed_s=.1, group_check='sole-zombie',
                 owned_pid=42, primary_class='none', cleanup_class='none', primary_errno=None,
                 cleanup_errno=None, errors=[], signals=[], stdout=stdout, stderr=b'',
                 stdout_count=len(stdout), stderr_count=0)
    return value


class Driver(unittest.TestCase):
    def sequence(self, target=None, helper=None, wall=None, live=False):
        allowed = Path('/private/tmp/easynet-g0-06-isolate-fake/allowed')
        value = dict(outcome='observed', stage='cat-image', operation='unknown',
                     termination='sigabrt', category='DYLD', code=1)
        raw = json.dumps(dict(record=value, reader_step='complete')).encode()
        module = types.SimpleNamespace(run_mapping_probe=Mock(return_value=target or result(code=-6)),
                                       _execute=Mock(return_value=helper or result(raw)), _live=live,
                                       _root=Mock(return_value=allowed.parent), check_fixture=Mock())
        progress = {"step": "preflight", "reader_step": "not-started"}
        with patch.object(d.os, 'environ', {'HOME': '/Users/runner'}), \
                patch.object(d.os, 'getpid', return_value=23), \
                patch.object(d, 'verify', return_value=Path('/fixed/python')) as verify, \
                patch.object(d.time, 'time_ns', side_effect=wall or [10**9, 1_100_000_000, 4_100_000_000, 4_200_000_000]), \
                patch.object(d.time, 'monotonic_ns', side_effect=[10**9, 1_100_000_000, 4_100_000_000, 4_200_000_000]), \
                patch.object(d.time, 'monotonic', return_value=4.3), patch.object(d.time, 'sleep') as sleep:
            try:
                got = d.sequence(module, mapping, r, allowed, 14, progress)
            except (ValueError, KeyError):
                got = r.unknown()
        self.step = progress["step"]
        self.reader_step = progress["reader_step"]
        return got, module, sleep, verify

    def test_fixed_once_and_guard_pairing(self):
        got, module, sleep, verify = self.sequence()
        self.assertEqual(got['outcome'], 'observed')
        self.assertEqual(self.step, 'reader-validation')
        self.assertEqual(self.reader_step, 'complete')
        module.run_mapping_probe.assert_called_once_with(d.LAB / 'mapping-fixture.sb',
            Path('/private/tmp/easynet-g0-06-isolate-fake/allowed'), 'sandbox-eof', 2)
        sleep.assert_called_once_with(3)
        module._execute.assert_called_once()
        argv, case, deadline = module._execute.call_args.args
        self.assertEqual(argv[:5], ['/fixed/python', '-I', '-B', str(d.LAB / 'attribution_record.py'), '--owned-ips-v1'])
        self.assertEqual(argv[5:7], ['42', '23'])
        self.assertEqual((len(argv), case, deadline), (11, 'owned-ips-v1', 2))
        self.assertEqual(verify.call_count, 4)

    def test_target_failure_stops_query(self):
        for changes in ({'returncode': 0}, {'reaped': False}, {'stderr': b'SECRET'}, {'owned_pid': True}):
            bad = result(code=-6)
            bad.update(changes)
            got, module, sleep, _ = self.sequence(target=bad)
            self.assertEqual(got, r.unknown())
            module._execute.assert_not_called()
            sleep.assert_not_called()
            self.assertEqual(self.step, "target-validation")

    def test_observer_independent_failures(self):
        for changes in ({'stdout': b'{"secret":"CANARY"}'}, {'stderr': b'SECRET'},
                        {'stderr_closed': False}, {'helper_wait_completed': False}, {'leader_wait_completed': False}):
            bad = result(json.dumps(dict(record=r.unknown(), reader_step='candidate-none')).encode())
            bad.update(changes)
            got, module, _, _ = self.sequence(helper=bad)
            self.assertEqual(got, r.unknown())
            self.assertEqual(module.run_mapping_probe.call_count, 1)
            self.assertEqual(module._execute.call_count, 1)
            self.assertEqual(self.step, 'reader-validation')
            self.assertEqual(self.reader_step, 'reader-invalid' if 'stdout' in changes else 'candidate-none')

    def test_clocks_and_live_state(self):
        for wall in ([10**9, 1_120_000_000], [10**9, 1_100_000_000, 4_200_000_000]):
            got, module, _, _ = self.sequence(wall=wall)
            self.assertEqual(got, r.unknown())
            module._execute.assert_not_called()
        got, module, _, _ = self.sequence(live=True)
        self.assertEqual(got, r.unknown())
        module._execute.assert_not_called()

    def test_main_rejects_host_without_fixture(self):
        with patch.object(d.os, 'environ', {}), patch.object(d.sys, 'argv', ['driver']), \
                patch.object(d.sys, 'platform', 'linux'), patch.object(d, 'fixture') as fixture, \
                patch.object(d, 'verify') as verify, patch.object(d.time, 'monotonic', return_value=0), \
                patch('builtins.print') as emit:
            self.assertEqual(d.main(), 1)
        fixture.assert_not_called()
        verify.assert_not_called()
        self.assertEqual(json.loads(emit.call_args.args[0]), dict(r.unknown(), driver_step="preflight", reader_step="not-started"))

    def test_main_cleanup_and_retention(self):
        fake_environment = {'HOME': '/Users/runner', 'GITHUB_ACTIONS': 'true',
                            'GITHUB_REPOSITORY': 'EasyIndie/EasyNet',
                            'GITHUB_REF': 'refs/heads/codex/feature/self-hosted-byos-byoc'}
        observed = dict(outcome='observed', stage='cat-image', operation='unknown',
                        termination='sigabrt', category='unknown', code=None)
        for fault in ('none', 'source', 'fixture', 'unknown', 'live', 'sequence', 'preclean-hash', 'postclean-hash', 'cleanup'):
            module = types.SimpleNamespace(_live=fault == 'live')
            fake_mapping = types.SimpleNamespace(clean_fixture=Mock(side_effect=ValueError() if fault == 'cleanup' else None))
            with ExitStack() as stack:
                for obj, key, value in ((d.os, 'environ', fake_environment), (d.sys, 'argv', ['driver']),
                        (d.sys, 'platform', 'darwin'), (d.sys, 'flags', types.SimpleNamespace(isolated=1)),
                        (d.sys, 'dont_write_bytecode', True)):
                    stack.enter_context(patch.object(obj, key, value))
                stack.enter_context(patch.object(d.os, 'getuid', return_value=501))
                stack.enter_context(patch.object(d.os, 'waitid', Mock(), create=True))
                stack.enter_context(patch.object(d.os, 'WNOWAIT', 1, create=True))
                stack.enter_context(patch.object(d.platform, 'machine', return_value='arm64'))
                stack.enter_context(patch.object(d.platform, 'mac_ver', return_value=('15.7.9', (), '')))
                for key in ('monotonic', 'monotonic_ns', 'time_ns'):
                    stack.enter_context(patch.object(d.time, key, return_value=0))
                effects = [ValueError()] if fault == 'source' else [None, ValueError()] if fault == 'preclean-hash' else [None, None, ValueError()] if fault == 'postclean-hash' else None
                stack.enter_context(patch.object(d, 'verify', side_effect=effects))
                stack.enter_context(patch.object(d, 'load', side_effect=[module, fake_mapping, r]))
                stack.enter_context(patch.object(d, 'fixture', return_value=Path('/fake/allowed'),
                                                side_effect=ValueError('SECRET') if fault == 'fixture' else None))
                def sequence(*args):
                    if fault == 'sequence':
                        raise ValueError()
                    args[-1]['reader_step'] = 'candidate-none' if fault == 'unknown' else 'complete'
                    return r.unknown() if fault == 'unknown' else observed
                stack.enter_context(patch.object(d, 'sequence', side_effect=sequence))
                emit = stack.enter_context(patch('builtins.print'))
                self.assertEqual(d.main(), 0 if fault == 'none' else 1)
            self.assertEqual(fake_mapping.clean_fixture.call_count, 1 if fault in ('none', 'postclean-hash', 'cleanup') else 0)
            steps = dict(none='complete', source='source', fixture='fixture', unknown='report',
                         live='report', sequence='target', **{'preclean-hash': 'report',
                         'postclean-hash': 'final-check', 'cleanup': 'cleanup'})
            self.assertEqual(json.loads(emit.call_args.args[0]),
                             dict(observed if fault == 'none' else r.unknown(), driver_step=steps[fault],
                                  reader_step='not-started' if fault in ('source', 'fixture', 'sequence')
                                  else 'candidate-none' if fault == 'unknown' else 'complete'))

    def test_source_hash_exact_set_and_interpreter(self):
        source = b'fake-reviewed-source'
        digest = hashlib.sha256(source).hexdigest()
        regular = types.SimpleNamespace(st_mode=0o100600, st_nlink=1)
        for fault in ('none', 'missing', 'extra', 'source', 'python'):
            hashes = dict.fromkeys(d.SOURCES, digest)
            if fault == 'missing':
                del hashes[d.SOURCES[0]]
            if fault == 'extra':
                hashes['unreviewed.py'] = digest
            if fault == 'source':
                hashes[d.SOURCES[0]] = '0'*64
            binding = json.dumps({'task_id': 'G0-06.2ar', 'status': 'frozen',
                                  'source_review': {'files_sha256': hashes}})
            with ExitStack() as stack:
                stack.enter_context(patch.object(d.os, 'environ', {}))
                stack.enter_context(patch.object(Path, 'read_text', return_value=binding))
                read = stack.enter_context(patch.object(Path, 'read_bytes', return_value=source))
                stack.enter_context(patch.object(Path, 'resolve', autospec=True, side_effect=lambda self, **kw: self))
                stack.enter_context(patch.object(Path, 'lstat', return_value=regular))
                stack.enter_context(patch.object(d.sys, 'executable', '/fixed/python'))
                stack.enter_context(patch.object(d.sys, 'version_info', (3,14,7)))
                stack.enter_context(patch.object(d, 'PYTHON_SHA', '0'*64 if fault == 'python' else digest))
                if fault == 'none':
                    self.assertEqual(d.verify(), Path('/fixed/python'))
                    self.assertEqual(read.call_count, len(d.SOURCES)+1)
                else:
                    with self.assertRaises(ValueError):
                        d.verify()
                    if fault in ('missing', 'extra'):
                        read.assert_not_called()


if __name__ == '__main__':
    unittest.main()
