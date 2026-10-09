"""Controlled in-memory records and FD fakes; no native commands or log reads."""
import importlib.util
import hashlib
import json
from pathlib import Path
import stat
import types
import unittest
from contextlib import ExitStack
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('record', Path(__file__).with_name('attribution_record.py'))
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)
driver_spec = importlib.util.spec_from_file_location('driver_binding', Path(__file__).with_name('attribution_diag.py'))
driver = importlib.util.module_from_spec(driver_spec)
driver_spec.loader.exec_module(driver)
T = 1_000_000_000
UUID = '12345678-1234-1234-1234-123456789abc'


def sample(name='cat'):
    path = '/bin/cat' if name == 'cat' else '/usr/bin/sandbox-exec'
    return ({'name': name, 'bug_type': '309', 'platform': 1, 'incident_id': UUID},
            {'incident': UUID, 'pid': 42, 'parentPid': 23,
             'procLaunch': '1970-01-01 00:00:01.010000000 +0000',
             'captureTime': '1970-01-01 00:00:04.000000000 +0000',
             'procName': name, 'procPath': path, 'cpuType': 'ARM-64', 'translated': False,
             'usedImages': [{'path': path, 'name': name, 'arch': 'arm64e', 'source': 'P', 'uuid': UUID}],
             'exception': {'signal': 'SIGABRT', 'message': 'SECRET-CANARY'},
             'termination': {'namespace': 'DYLD', 'code': 1, 'reason': 'SECRET-CANARY'}})


def encode(meta, body):
    return (json.dumps(meta) + '\n' + json.dumps(body)).encode()


def observe(raw):
    return r.parse_record(raw, 42, 23, T, T + 20_000_000, 4*T)


class Parser(unittest.TestCase):
    def test_images_and_sanitization(self):
        for name in ('cat', 'sandbox-exec'):
            value = observe(encode(*sample(name)))
            self.assertEqual(value['stage'], name + '-image')
            self.assertNotIn('SECRET', json.dumps(value))
            self.assertEqual(r.sanitized(json.dumps(value).encode()), value)

    def test_private_envelope_strict_and_no_record_phase_authority(self):
        value = observe(encode(*sample()))
        for phase in r.READER_STEPS:
            wire = json.dumps(dict(record=value, reader_step=phase)).encode()
            self.assertEqual(r.sanitized_envelope(wire), dict(record=value, reader_step=phase))
        for wire in (json.dumps(dict(record=value, reader_step='SECRET-CANARY')).encode(),
                     json.dumps(dict(record=value, reader_step=True)).encode(),
                     json.dumps(dict(record=value, reader_step=[])).encode(),
                     json.dumps(dict(record=value, reader_step='parse', extra='SECRET-CANARY')).encode(),
                     json.dumps(dict(record=dict(value, extra='SECRET-CANARY'), reader_step='parse')).encode(),
                     json.dumps(dict(record=value, reader_step=[], extra='SECRET-CANARY')).encode(),
                     json.dumps(dict(record=dict(value, reader_step='complete'), reader_step='parse')).encode(),
                     b'{"record":{},"reader_step":"parse","reader_step":"complete"}',
                     b'{"record":{"outcome":"unknown","outcome":"observed"},"reader_step":"parse"}',
                     json.dumps(value).encode(), b' ' * 513):
            with self.assertRaises((ValueError, TypeError)):
                r.sanitized_envelope(wire)
        meta, body = sample()
        body['reader_step'] = 'SECRET-CANARY'
        self.assertEqual(set(observe(encode(meta, body))), r.KEYS)

    def test_identity_rejection(self):
        variants = {'pid': [43, True], 'parentPid': [24, True], 'procPath': ['/bin/false'],
                    'procName': ['other'], 'cpuType': ['X86-64'], 'translated': [True],
                    'procLaunch': ['1970-01-01 00:00:01.030 +0000', '1970-01-01T00:00:01'],
                    'captureTime': ['1970-01-01 00:00:00 +0000', '1970-01-01 00:00:05 +0000'],
                    'incident': ['other'], 'simulated': [True], 'isNonFatal': [True]}
        for key, values in variants.items():
            for value in values:
                meta, body = sample()
                body[key] = value
                self.assertEqual(observe(encode(meta, body)), r.unknown(), (key, value))
        for key in sample()[1]:
            meta, body = sample()
            if key != 'termination':
                del body[key]
                self.assertEqual(observe(encode(meta, body)), r.unknown(), key)

    def test_images_signals_categories(self):
        for key, value in [('arch', 'x86_64'), ('uuid', 'redacted'), ('source', 'S'), ('path', '/bad')]:
            meta, body = sample()
            body['usedImages'][0][key] = value
            self.assertEqual(observe(encode(meta, body)), r.unknown())
        meta, body = sample()
        body['usedImages'] *= 2
        self.assertEqual(observe(encode(meta, body)), r.unknown())
        for category in ('DYLD', 'SANDBOX', 'CODESIGNING', 'SIGNAL'):
            for code in (0, 65535):
                meta, body = sample()
                body['termination'] = {'namespace': category, 'code': code}
                self.assertEqual(observe(encode(meta, body))['code'], code)
        for category, code in [('OTHER', 1), ('DYLD', True), ('DYLD', -1), ('DYLD', 65536), ('DYLD', '1')]:
            meta, body = sample()
            body['termination'] = {'namespace': category, 'code': code}
            value = observe(encode(meta, body))
            self.assertEqual((value['category'], value['code']), ('unknown', None))
        meta, body = sample()
        body['exception']['signal'] = 'SIGKILL'
        self.assertEqual(observe(encode(meta, body)), r.unknown())

    def test_malformed_and_strict_schema(self):
        raw = encode(*sample())
        for bad in (raw[:-1], raw + b'{}', b'\xff', b'{}\nNaN', raw.replace(b'"pid": 42', b'"pid": 42,"pid": 42'),
                    raw.replace(b'"code": 1', b'"code": 1e999'),
                    b'{}\n' + b'['*34 + b'0' + b']'*34, b'x'*(r.LIMIT+1)):
            self.assertEqual(observe(bad), r.unknown())
        for value in (dict(r.unknown(), extra='SECRET'), dict(r.unknown(), code=True), {}, []):
            with self.assertRaises(ValueError):
                r.sanitized(json.dumps(value).encode())
        with self.assertRaises(ValueError):
            r.sanitized(b' ' * 513)
        self.assertEqual(r.timestamp('1970-01-01T01:00:01.123456789+01:00'), T + 123456789)
        self.assertFalse(r.clocks(20, 50, 0, 0, 10))
        self.assertFalse(r.clocks(0, 20_000_000, 0, 0))
        with self.assertRaises(ValueError):
            r.internal_args(['--owned-ips-v1', '42', '23', '1', '2', '3', 'True'])


def info(mode=stat.S_IFREG | 0o600, size=0, nlink=1, uid=501, stamp=2*T):
    return types.SimpleNamespace(st_dev=1, st_ino=8, st_mode=mode, st_uid=uid, st_nlink=nlink,
                                 st_size=size, st_mtime_ns=stamp, st_ctime_ns=stamp)


class Iterator:
    def __init__(self, names):
        self.names, self.closed = names, False
    def __iter__(self):
        return iter(types.SimpleNamespace(name=name) for name in self.names)
    def close(self):
        self.closed = True


class Filesystem(unittest.TestCase):
    def fake_scan(self, names=('cat-test.ips',), report=None, candidate=None, mutation=False,
                  fail_open=False, clock_jump=False, fail_read=False, close_error=False,
                  elapsed=False, delayed_close=False, teardown_jump=False, initial_identity=False,
                  fail_record_open=False, directory_guard=False, iterator_close=False, legacy=False):
        raw = encode(*sample()) if report is None else report
        candidate = candidate or info(size=len(raw))
        iterator, closed, opened, reads, consumed = Iterator(names), [], [], [], [0]
        teardown = [False]
        progress = {}
        def opening(name, flags, **kwargs):
            if (fail_open and name == 'Logs') or (fail_record_open and name.endswith('.ips')):
                raise OSError()
            opened.append((name, flags, kwargs))
            return len(opened)
        def fstat(fd):
            if fd <= 6:
                return info(stat.S_IFDIR | (0o722 if directory_guard else 0o700))
            if initial_identity or (mutation and reads):
                return info(size=len(raw)+1)
            return candidate
        def reading(fd, cap):
            reads.append(cap)
            if fail_read:
                raise OSError()
            chunk = raw[consumed[0]:consumed[0]+cap]
            consumed[0] += len(chunk)
            return chunk
        def closing(fd):
            closed.append(fd)
            teardown[0] = True
            if close_error and fd == 7:
                raise OSError()
        def clock(mono=False):
            delay = 600_000_000 if (elapsed and scandir.called) or (delayed_close and teardown[0]) else 0
            jump = 20_000_000 if mono and (clock_jump or (teardown_jump and teardown[0])) else 0
            return 4*T + delay + jump
        if iterator_close:
            iterator.close = unittest.mock.Mock(side_effect=OSError())
        with patch.object(r.os, 'environ', {'HOME': '/Users/runner'}), \
                patch.object(r.os, 'getuid', return_value=501), patch.object(r.os, 'open', side_effect=opening), \
                patch.object(r.os, 'fstat', side_effect=fstat), patch.object(r.os, 'scandir', return_value=iterator) as scandir, \
                patch.object(r.os, 'stat', return_value=candidate), patch.object(r.os, 'read', side_effect=reading), \
                patch.object(r.os, 'close', side_effect=closing), patch.object(r.time, 'time_ns', side_effect=clock), \
                patch.object(r.time, 'monotonic_ns', side_effect=lambda: clock(True)):
            args = (42, 23, T, T+20_000_000, 4*T, 4*T)
            value = r.scan(*args) if legacy else r.scan(*args, progress)
        self.assertEqual(set(closed), set(range(1, len(opened)+1)))
        if scandir.called:
            if iterator_close:
                iterator.close.assert_called_once()
            else:
                self.assertTrue(iterator.closed)
        self.assertTrue(all(0 < cap <= 65536 for cap in reads))
        self.assertLessEqual(consumed[0], candidate.st_size + 1)
        self.reader_step = progress.get("step")
        return value, reads, opened

    def test_owned_scan_and_fd_closure(self):
        self.assertEqual(self.fake_scan(legacy=True)[0]['outcome'], 'observed')
        value, reads, opened = self.fake_scan()
        self.assertEqual(value['outcome'], 'observed')
        self.assertTrue(all(flags & r.os.O_NOFOLLOW for _, flags, _ in opened))
        self.assertLessEqual(sum(reads), r.LIMIT+1)
        for options in ({'mutation': True}, {'fail_open': True}, {'fail_read': True}, {'clock_jump': True},
                        {'close_error': True}, {'elapsed': True}, {'delayed_close': True},
                        {'teardown_jump': True}, {'report': b'bad'}, {'names': ()},
                        {'names': ('cat-one.ips', 'cat-two.ips')}, {'names': ('other',)*257}):
            self.assertEqual(self.fake_scan(**options)[0], r.unknown())

    def test_finite_scan_fault_phases(self):
        cases = (({'names': ()}, 'candidate-none'),
                 ({'names': ('cat-one.ips', 'cat-two.ips')}, 'candidate-ambiguous'),
                 ({'candidate': info(size=r.LIMIT+1)}, 'candidate-size'),
                 ({'names': ('other',)*257}, 'entry-limit'),
                 ({'initial_identity': True}, 'record-identity'),
                 ({'mutation': True}, 'record-identity'),
                 ({'fail_read': True}, 'record-read'),
                 ({'fail_record_open': True}, 'record-open'),
                 ({'fail_open': True}, 'directory-open'),
                 ({'directory_guard': True}, 'directory-guard'),
                 ({'clock_jump': True}, 'scan-cleanup'),
                 ({'report': b'bad'}, 'record-rejected'),
                 ({'close_error': True}, 'scan-cleanup'),
                 ({'iterator_close': True}, 'scan-cleanup'),
                 ({'delayed_close': True}, 'scan-cleanup'))
        for options, phase in cases:
            self.assertEqual(self.fake_scan(**options)[0], r.unknown())
            self.assertEqual(self.reader_step, phase, options)

    def test_candidate_rejections_no_read(self):
        for candidate in (info(stat.S_IFLNK | 0o600), info(nlink=2), info(uid=502),
                          info(size=r.LIMIT+1), info(stamp=T-1), info(stamp=5*T),
                          info(stat.S_IFREG | 0o622)):
            value, reads, _ = self.fake_scan(candidate=candidate)
            self.assertEqual(value, r.unknown())
            self.assertEqual(reads, [])

    def test_chunked_read_limit_and_growth(self):
        raw = encode(*sample())
        value, reads, _ = self.fake_scan(report=raw + b' '*(r.LIMIT-len(raw)))
        self.assertEqual(value['outcome'], 'observed')
        self.assertEqual(sum(reads), r.LIMIT + 1)
        value, reads, _ = self.fake_scan(report=raw + b'x', candidate=info(size=len(raw)))
        self.assertEqual(value, r.unknown())
        self.assertEqual(sum(reads), len(raw)+1)


class ReaderGuard(unittest.TestCase):
    def test_internal_guest_and_hash_failures(self):
        source = b'def verify():\n    pass\n'
        args = ['reader', '--owned-ips-v1', '42', '23', str(T), str(T+10), str(4*T), str(4*T)]
        for fault in ('none', 'arguments', 'parent', 'home', 'version', 'binding-read', 'hash', 'guard-load',
                      'prehash', 'posthash', 'guard-binding', 'legacy-only', 'unknown'):
            digest = hashlib.sha256(source).hexdigest() if fault != 'hash' else '0'*64
            binding = json.dumps({'source_review': {'files_sha256': {'poc/client-framework/lab/attribution_diag.py': digest}}})
            with ExitStack() as stack:
                for obj, key, value in ((r.os, 'environ', {'HOME': '/other' if fault == 'home' else '/Users/runner'}),
                        (r.sys, 'argv', ['reader'] if fault == 'arguments' else args), (r.sys, 'platform', 'darwin'), (r.sys, 'version_info', (3,14,6) if fault == 'version' else (3,14,7)),
                        (r.sys, 'flags', types.SimpleNamespace(isolated=1)), (r.sys, 'dont_write_bytecode', True)):
                    stack.enter_context(patch.object(obj, key, value))
                stack.enter_context(patch.object(r.os, 'getuid', return_value=501))
                stack.enter_context(patch.object(r.os, 'getppid', return_value=24 if fault == 'parent' else 23))
                stack.enter_context(patch.object(r.platform, 'machine', return_value='arm64'))
                stack.enter_context(patch.object(r.platform, 'mac_ver', return_value=('15.7.9', (), '')))
                for key in ('monotonic', 'monotonic_ns', 'time_ns'):
                    stack.enter_context(patch.object(r.time, key, return_value=0))
                binding_reads = []
                def read_binding(path, *_args, **_kwargs):
                    binding_reads.append(path)
                    expected = (driver.BINDING.with_name('G0-06.2an.json')
                                if fault == 'legacy-only' else driver.BINDING)
                    if fault == 'binding-read' or path != expected:
                        raise ValueError('unreviewed binding path')
                    return binding
                stack.enter_context(patch.object(Path, 'read_text', autospec=True, side_effect=read_binding))
                stack.enter_context(patch.object(Path, 'read_bytes', return_value=source))
                fake_guard = types.ModuleType('guard')
                stack.enter_context(patch.object(r.importlib.util, 'module_from_spec', return_value=fake_guard))
                def fake_exec(*_):
                    if fault == "guard-load":
                        raise ValueError()
                    fake_guard.BINDING = (driver.BINDING.with_name('G0-06.2an.json')
                                          if fault == 'guard-binding' else driver.BINDING)
                    fake_guard.verify = unittest.mock.Mock(side_effect=[ValueError()] if fault == 'prehash' else [None, ValueError()] if fault == 'posthash' else [None, None])
                stack.enter_context(patch.object(r, 'exec', side_effect=fake_exec, create=True))
                def fake_scan(*args, progress):
                    progress['step'] = 'candidate-none' if fault == 'unknown' else 'parse'
                    return r.unknown() if fault == 'unknown' else observe(encode(*sample()))
                scan = stack.enter_context(patch.object(r, 'scan', side_effect=fake_scan))
                emit = stack.enter_context(patch('builtins.print'))
                r.main()
            self.assertEqual(json.loads(emit.call_args.args[0])['record']['outcome'], 'observed' if fault == 'none' else 'unknown')
            self.assertEqual(scan.call_count, 1 if fault in ('none', 'posthash', 'unknown') else 0)
            self.assertEqual(binding_reads, [] if fault in ('arguments', 'parent', 'home', 'version') else [driver.BINDING])
            phases = {'none': 'complete', 'arguments': 'arguments', 'parent': 'guest',
                      'home': 'guest', 'version': 'guest', 'binding-read': 'binding-read',
                      'hash': 'guard-source', 'guard-load': 'guard-load', 'prehash': 'pre-scan-hash',
                      'posthash': 'post-scan-hash', 'guard-binding': 'binding-match',
                      'legacy-only': 'binding-read', 'unknown': 'candidate-none'}
            self.assertEqual(json.loads(emit.call_args.args[0])['reader_step'], phases[fault])
            if fault == 'guard-binding':
                fake_guard.verify.assert_not_called()


if __name__ == '__main__':
    unittest.main()
