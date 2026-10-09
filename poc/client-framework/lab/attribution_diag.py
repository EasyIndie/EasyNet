"""Fixed one-shot guest attribution driver. Importing performs no native I/O."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import stat
import sys
import tempfile
import time
import uuid

LAB = Path(__file__).absolute().parent
ROOT = LAB.parents[2]
BINDING = ROOT / 'docs/planning/task-bindings/G0-06.2ar.json'
OLD = ('isolate.py', 'mapping-fixture.sb', 'mapping_diag.py', 'mapping_diag_test.py',
       'mapping_main_test.py', 'fixture.sb')
NEW = ('attribution_diag.py', 'attribution_record.py', 'attribution_record_test.py',
       'attribution_diag_test.py')
SOURCES = tuple('poc/client-framework/lab/' + name for name in OLD + NEW) + (
    '.github/workflows/client-startup-attribution.yml',)
PYTHON_SHA = 'd8f1d508de5acfd500f20d1949528375ff4a1f470efb267f00d1770941cdeee3'


def require(condition):
    if not condition:
        raise ValueError('fixed guard')


def verify():
    """Missing root-reviewed hashes fail closed; exact paths only."""
    def unique(items):
        value = {}
        for key, item in items:
            require(key not in value)
            value[key] = item
        return value
    binding = json.loads(BINDING.read_text(), object_pairs_hook=unique)
    require(binding['task_id'] == 'G0-06.2ar' and binding['status'] == 'frozen')
    hashes = binding['source_review']['files_sha256']
    require(type(hashes) is dict and set(hashes) == set(SOURCES))
    for name, digest in hashes.items():
        path = ROOT / name
        require(type(digest) is str and len(digest) == 64
                and path.resolve(strict=True) == path and stat.S_ISREG(path.lstat().st_mode)
                and path.lstat().st_nlink == 1 and not path.lstat().st_mode & 0o022)
        require(hashlib.sha256(path.read_bytes()).hexdigest() == digest)
    executable = Path(sys.executable).resolve(strict=True)
    require(sys.version_info[:3] == (3, 14, 7)
            and hashlib.sha256(executable.read_bytes()).hexdigest() == PYTHON_SHA)
    return executable


def load(name):
    verify()
    spec = importlib.util.spec_from_file_location('attribution_' + name, LAB / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    source = (LAB / (name + '.py')).read_bytes()
    verify()
    expected = json.loads(BINDING.read_text())['source_review']['files_sha256'][
        'poc/client-framework/lab/' + name + '.py']
    require(hashlib.sha256(source).hexdigest() == expected)
    exec(compile(source, str(LAB / (name + '.py')), 'exec'), module.__dict__)
    verify()
    return module


def fixture(module, end):
    require(time.monotonic() < end)
    root = Path(tempfile.mkdtemp(prefix='easynet-g0-06-isolate-', dir='/private/tmp'))
    os.chmod(root, 0o700)
    for name in ('allowed', 'decoy'):
        require(time.monotonic() < end)
        directory = root / name
        directory.mkdir(mode=0o700)
        os.chmod(directory, 0o700)
        fd = os.open(directory / 'seed', os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'wb') as stream:
            os.fchmod(stream.fileno(), 0o600)
            stream.write(uuid.uuid4().hex.encode())
    require(time.monotonic() < end)
    module.freeze_fixture(root / 'allowed')
    require(time.monotonic() < end)
    return root / 'allowed'


def sequence(module, mapping, record, allowed, end, progress):
    """One B target and one internal reader; uncertainty stops further launches."""
    progress["step"] = "source"
    executable = verify()
    parent = os.getpid()
    t0, m0 = time.time_ns(), time.monotonic_ns()
    progress["step"] = "target"
    target = module.run_mapping_probe(LAB / 'mapping-fixture.sb', allowed, 'sandbox-eof', 2)
    progress["step"] = "target-validation"
    t1, m1 = time.time_ns(), time.monotonic_ns()
    verify()
    require(mapping.healthy(target, b'', returncode=-6)
            and record.clocks(t1, m1, t0, m0, 999_999_999) and time.monotonic() < end)
    progress["step"] = "delivery"
    time.sleep(3)
    verify()
    wall, mono = time.time_ns(), time.monotonic_ns()
    require(record.clocks(wall, mono, t0, m0) and time.monotonic() + 2 < end)
    progress["step"] = "reader-arguments"
    args = tuple(str(item) for item in (target['owned_pid'], parent, t0, t1, wall, mono))
    require(record.internal_args(['--owned-ips-v1', *args]) == (
        target['owned_pid'], parent, t0, t1, wall, mono))
    require(not module._live and allowed == module._root(allowed) / 'allowed')
    module.check_fixture(allowed)
    progress["step"] = "reader"
    helper = module._execute([str(executable), '-I', '-B', str(LAB / 'attribution_record.py'),
                              '--owned-ips-v1', *args], 'owned-ips-v1', 2)
    progress["step"] = "reader-validation"
    after_wall, after_mono = time.time_ns(), time.monotonic_ns()
    verify()
    progress['reader_step'] = 'reader-invalid'
    envelope = record.sanitized_envelope(helper['stdout'])
    progress['reader_step'] = envelope['reader_step']
    value = envelope['record']
    require(mapping.healthy(helper, helper['stdout']) and record.clocks(after_wall, after_mono, t0, m0)
            and time.monotonic() < end)
    return value


def main():
    start = time.monotonic()
    end = start + 14
    value = dict(outcome='unknown', stage='unknown', operation='unknown',
                 termination='unknown', category='unknown', code=None)
    progress = {"step": "preflight", "reader_step": "not-started"}
    try:
        require(not sys.argv[1:] and sys.platform == 'darwin' and platform.machine() == 'arm64'
                and platform.mac_ver()[0] == '15.7.9' and os.getuid() != 0
                and os.environ.get('HOME') == '/Users/runner'
                and os.environ.get('GITHUB_ACTIONS') == 'true'
                and os.environ.get('GITHUB_REPOSITORY') == 'EasyIndie/EasyNet'
                and os.environ.get('GITHUB_REF') == 'refs/heads/codex/feature/self-hosted-byos-byoc'
                and sys.flags.isolated and sys.dont_write_bytecode
                and hasattr(os, 'waitid') and hasattr(os, 'WNOWAIT'))
        progress["step"] = "source"
        verify()
        module, mapping, record = load('isolate'), load('mapping_diag'), load('attribution_record')
        progress["step"] = "fixture"
        allowed = fixture(module, start + 4)
        progress["step"] = "target"
        value = sequence(module, mapping, record, allowed, end, progress)
        progress["step"] = "report"
        require(value['outcome'] == 'observed' and not module._live)
        verify()
        progress["step"] = "cleanup"
        mapping.clean_fixture(module, allowed, min(end, time.monotonic() + 3))
        progress["step"] = "final-check"
        verify()
        require(time.monotonic() < end)
        progress["step"] = "complete"
    except Exception:
        value = dict(outcome='unknown', stage='unknown', operation='unknown',
                     termination='unknown', category='unknown', code=None)
    value = dict(value, driver_step=progress["step"], reader_step=progress["reader_step"])
    print(json.dumps(value, sort_keys=True, separators=(',', ':')))
    return 0 if value['outcome'] == 'observed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
