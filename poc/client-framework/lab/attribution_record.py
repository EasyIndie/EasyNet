"""Import-safe, bounded owned IPS observation; never exports report content."""
import datetime
import importlib.util
import json
import math
import os
from pathlib import Path
import platform
import re
import stat
import sys
import time
import uuid

KEYS = {'outcome', 'stage', 'operation', 'termination', 'category', 'code'}
CATEGORIES = {'DYLD', 'SANDBOX', 'CODESIGNING', 'SIGNAL'}
NAME = re.compile(r'(cat|sandbox-exec)[-_][A-Za-z0-9._-]{1,160}\.ips')
LIMIT = 262144


def unknown():
    return dict(outcome='unknown', stage='unknown', operation='unknown',
                termination='unknown', category='unknown', code=None)


def pairs(items):
    result = {}
    for key, value in items:
        if key in result:
            raise ValueError('duplicate')
        result[key] = value
    return result


def depth(value, level=0):
    if level > 32:
        raise ValueError('depth')
    if type(value) is float and not math.isfinite(value):
        raise ValueError('nonfinite')
    if isinstance(value, dict):
        for item in value.values():
            depth(item, level + 1)
    elif isinstance(value, list):
        for item in value:
            depth(item, level + 1)


def loads(value):
    def invalid(_):
        raise ValueError('nonfinite')
    result = json.loads(value, object_pairs_hook=pairs, parse_constant=invalid)
    depth(result)
    return result


def timestamp(value):
    if type(value) is not str:
        raise ValueError('time')
    match = re.fullmatch(r'(\d{4}-\d\d-\d\d)[ T](\d\d:\d\d:\d\d)(?:\.(\d{1,9}))? ?(Z|[+-]\d\d:?\d\d)', value)
    if not match:
        raise ValueError('time')
    day, clock, fraction, offset = match.groups()
    if offset == 'Z':
        offset = '+00:00'
    elif ':' not in offset:
        offset = offset[:3] + ':' + offset[3:]
    zone_hours, zone_minutes = int(offset[1:3]), int(offset[4:])
    if zone_hours > 23 or zone_minutes > 59:
        raise ValueError('offset')
    parsed = datetime.datetime.fromisoformat(day + 'T' + clock + offset)
    delta = parsed.astimezone(datetime.timezone.utc) - datetime.datetime(1970, 1, 1, tzinfo=datetime.timezone.utc)
    return (delta.days * 86400 + delta.seconds) * 10**9 + int((fraction or '').ljust(9, '0'))


def parse_record(raw, pid, parent, t0, t1, query_end):
    try:
        if type(raw) is not bytes or len(raw) > LIMIT:
            return unknown()
        header, body = raw.decode('utf-8', 'strict').split('\n', 1)
        meta, report = loads(header), loads(body)
        if type(meta) is not dict or type(report) is not dict:
            return unknown()
        name = meta['name']
        if (name not in ('cat', 'sandbox-exec') or meta['bug_type'] != '309'
                or type(meta['platform']) is not int or meta['platform'] != 1
                or type(meta['incident_id']) is not str
                or str(uuid.UUID(meta['incident_id'])).lower() != meta['incident_id'].lower()
                or meta['incident_id'] != report['incident']
                or any(obj.get('simulated', False) is not False or obj.get('isNonFatal', False) is not False
                       for obj in (meta, report))):
            return unknown()
        path = '/bin/cat' if name == 'cat' else '/usr/bin/sandbox-exec'
        launch, capture = timestamp(report['procLaunch']), timestamp(report['captureTime'])
        if (type(report['pid']) is not int or report['pid'] != pid
                or type(report['parentPid']) is not int or report['parentPid'] != parent
                or not t0 <= launch <= t1 or not launch <= capture <= query_end
                or report['procName'] != name or report['procPath'] != path
                or report['cpuType'] != 'ARM-64' or report['translated'] is not False
                or type(report['usedImages']) is not list
                or any(type(item) is not dict for item in report['usedImages'])):
            return unknown()
        images = [item for item in report['usedImages'] if type(item) is dict
                  and (item.get('path') == path or item.get('name') == name)]
        if len(images) != 1:
            return unknown()
        image = images[0]
        if (image['path'] != path or image['name'] != name
                or image['arch'] not in ('arm64', 'arm64e') or image['source'] != 'P'
                or type(image['uuid']) is not str
                or str(uuid.UUID(image['uuid'])).lower() != image['uuid'].lower()
                or report['exception']['signal'] != 'SIGABRT'):
            return unknown()
        reason = report.get('termination', {})
        category, code = reason.get('namespace'), reason.get('code')
        if category not in CATEGORIES or type(code) is not int or not 0 <= code <= 65535:
            category, code = 'unknown', None
        return dict(outcome='observed', stage=name + '-image', operation='unknown',
                    termination='sigabrt', category=category, code=code)
    except (ValueError, TypeError, KeyError, AttributeError, UnicodeError, RecursionError):
        return unknown()


def sanitized(raw):
    if type(raw) is not bytes or not 0 < len(raw) <= 512:
        raise ValueError('output bounds')
    value = loads(raw.decode('utf-8', 'strict'))
    if type(value) is not dict or set(value) != KEYS:
        raise ValueError('schema')
    if value == unknown():
        return value
    if (value['outcome'] != 'observed' or value['stage'] not in ('cat-image', 'sandbox-exec-image')
            or value['operation'] != 'unknown' or value['termination'] != 'sigabrt'
            or not ((value['category'] == 'unknown' and value['code'] is None)
                    or (value['category'] in CATEGORIES and type(value['code']) is int
                        and 0 <= value['code'] <= 65535))):
        raise ValueError('enum')
    return value


def clocks(wall, mono, base_wall, base_mono, maximum=None):
    dw, dm = wall - base_wall, mono - base_mono
    return (dw >= 0 and dm >= 0 and abs(dw - dm) <= 10_000_000
            and (maximum is None or max(dw, dm) <= maximum))


def identity(s):
    return (s.st_dev, s.st_ino, s.st_mode, s.st_uid, s.st_nlink,
            s.st_size, s.st_mtime_ns, s.st_ctime_ns)


def scan(pid, parent, t0, t1, query_wall, query_mono):
    """Exactly one flat pass, one qualifying candidate at most, independent FD close."""
    descriptors, iterator, start_wall, start_mono = [], None, None, None
    result = unknown()
    def query():
        nonlocal iterator, start_wall, start_mono
        uid = os.getuid()
        start_wall, start_mono = time.time_ns(), time.monotonic_ns()
        if not clocks(start_wall, start_mono, query_wall, query_mono, 10**9):
            return unknown()
        def checked():
            wall, mono = time.time_ns(), time.monotonic_ns()
            if mono - start_mono > 500_000_000 or not clocks(wall, mono, query_wall, query_mono):
                raise ValueError('clock')
            return wall
        flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_DIRECTORY | os.O_NONBLOCK
        fd = os.open('/', flags)
        descriptors.append(fd)
        root_stat = os.fstat(fd)
        if not stat.S_ISDIR(root_stat.st_mode) or root_stat.st_uid not in (0, uid) or root_stat.st_mode & 0o022:
            return unknown()
        for component in ('Users', 'runner', 'Library', 'Logs', 'DiagnosticReports'):
            checked()
            fd = os.open(component, flags, dir_fd=fd)
            descriptors.append(fd)
            s = os.fstat(fd)
            if (not stat.S_ISDIR(s.st_mode) or s.st_uid not in (0, uid)
                    or s.st_mode & 0o022 or (component == 'DiagnosticReports' and s.st_uid != uid)):
                return unknown()
        candidate = None
        iterator = os.scandir(fd)
        for count, entry in enumerate(iterator, 1):
            checked()
            if count > 256:
                return unknown()
            if not NAME.fullmatch(entry.name):
                continue
            s = os.stat(entry.name, dir_fd=fd, follow_symlinks=False)
            end_wall = checked()
            if (stat.S_ISREG(s.st_mode) and s.st_uid == uid and s.st_nlink == 1
                    and not s.st_mode & 0o022 and t0 <= s.st_mtime_ns <= end_wall
                    and t0 <= s.st_ctime_ns <= end_wall):
                if candidate is not None:
                    return unknown()
                candidate = (entry.name, s)
        checked()
        if candidate is None or candidate[1].st_size > LIMIT:
            return unknown()
        name, before = candidate
        report_fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
        descriptors.append(report_fd)
        if identity(os.fstat(report_fd)) != identity(before):
            return unknown()
        data = bytearray()
        while len(data) <= before.st_size:
            checked()
            chunk = os.read(report_fd, min(65536, before.st_size + 1 - len(data)))
            if not chunk:
                break
            data.extend(chunk)
        end_wall = checked()
        if len(data) != before.st_size or identity(os.fstat(report_fd)) != identity(before):
            return unknown()
        result = parse_record(bytes(data), pid, parent, t0, t1, end_wall)
        checked()
        return result
    try:
        result = query()
    except (OSError, ValueError, TypeError, OverflowError):
        result = unknown()
    finally:
        close_failed = False
        if iterator is not None:
            try:
                iterator.close()
            except OSError:
                close_failed = True
        for descriptor in reversed(descriptors):
            try:
                os.close(descriptor)
            except OSError:
                close_failed = True
        try:
            wall, mono = time.time_ns(), time.monotonic_ns()
            if (start_mono is None or mono - start_mono > 500_000_000
                    or not clocks(wall, mono, query_wall, query_mono)):
                close_failed = True
        except (OSError, ValueError, TypeError, OverflowError):
            close_failed = True
        if close_failed:
            result = unknown()
    return result


def internal_args(argv):
    if len(argv) != 7 or argv[0] != '--owned-ips-v1':
        raise ValueError('token')
    if any(type(item) is not str or not re.fullmatch(r'[1-9][0-9]{0,18}', item) for item in argv[1:]):
        raise ValueError('numbers')
    values = tuple(int(item) for item in argv[1:])
    pid, parent, t0, t1, wall, mono = values
    if pid > 2**31 - 1 or parent > 2**31 - 1 or not t0 <= t1 < t0 + 10**9 or wall < t1:
        raise ValueError('bounds')
    return values


def main():
    value = unknown()
    try:
        args = internal_args(sys.argv[1:])
        if (sys.platform != 'darwin' or platform.machine() != 'arm64' or os.getuid() == 0
                or os.environ.get('HOME') != '/Users/runner' or os.getppid() != args[1]
                or sys.version_info[:3] != (3, 14, 7) or platform.mac_ver()[0] != '15.7.9'
                or not sys.flags.isolated or not sys.dont_write_bytecode):
            raise ValueError('guest')
        path = Path(__file__).absolute().with_name('attribution_diag.py')
        binding_path = path.parents[3] / 'docs/planning/task-bindings/G0-06.2an.json'
        binding = loads(binding_path.read_text())
        source = path.read_bytes()
        import hashlib
        if hashlib.sha256(source).hexdigest() != binding['source_review']['files_sha256'][
                'poc/client-framework/lab/attribution_diag.py']:
            raise ValueError('source')
        spec = importlib.util.spec_from_file_location('owned_attribution_guard', path)
        guard = importlib.util.module_from_spec(spec)
        exec(compile(source, str(path), 'exec'), guard.__dict__)
        guard.verify()
        value = scan(*args)
        guard.verify()
    except Exception:
        value = unknown()
    print(json.dumps(value, sort_keys=True, separators=(',', ':')))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
