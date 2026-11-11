#!/usr/bin/python3 -I
"""Root-owned, fixed APT interface. Never accepts shell commands or APT options."""
import fcntl
import gzip
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import time
from urllib.parse import urlsplit, urlunsplit

OPERATIONS = {'status', 'search', 'show', 'plan', 'install', 'docs', 'refresh', 'catalog', 'sources'}
ORIGINS = {'Ubuntu', 'UbuntuESM', 'UbuntuESMApps', 'UbuntuESMInfra'}
PACKAGE = re.compile(r'[a-z0-9][a-z0-9+.-]{1,100}\Z')
ENV = {'PATH': '/usr/sbin:/usr/bin:/sbin:/bin', 'HOME': '/root', 'LC_ALL': 'C', 'DEBIAN_FRONTEND': 'noninteractive'}


def validate(request):
    if not isinstance(request, dict) or set(request) - {'operation', 'package'}:
        raise ValueError('Unknown package request fields')
    operation = request.get('operation')
    if operation not in OPERATIONS:
        raise ValueError('Unknown package operation')
    value = request.get('package', '')
    if operation in ('search', 'catalog'):
        if not isinstance(value, str) or not re.fullmatch(r'[a-zA-Z0-9+._ -]{1,100}', value):
            raise ValueError('Use a short package search phrase')
    elif operation not in ('status', 'refresh', 'sources') and (not isinstance(value, str) or not PACKAGE.fullmatch(value)):
        raise ValueError('Use one Ubuntu package name, without options or paths')
    return operation, value


def run(argv, timeout=120):
    # A tempfile bounds memory even when APT is verbose. No shell or inherited credentials.
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        result = subprocess.run(argv, stdin=subprocess.DEVNULL, stdout=out, stderr=err, env=ENV, timeout=timeout, check=False)
        out.seek(0); err.seek(0)
        stdout = out.read(100000).decode('utf-8', 'replace')
        stderr = err.read(10000).decode('utf-8', 'replace')
    if result.returncode:
        raise ValueError('Package command failed: ' + (stderr or stdout)[-4000:])
    return stdout


def ubuntu():
    values = {}
    for line in pathlib.Path('/etc/os-release').read_text().splitlines():
        if '=' in line:
            key, value = line.split('=', 1); values[key] = value.strip('"')
    if values.get('ID') != 'ubuntu':
        raise ValueError('This package interface requires an Ubuntu host')
    return values


def trusted(version):
    return bool(version and any(origin.origin in ORIGINS and origin.trusted for origin in version.origins))


def metadata(pkg):
    version = pkg.candidate or pkg.installed
    return {'package': pkg.name, 'candidate': pkg.candidate.version if pkg.candidate else None,
            'installed_version': pkg.installed.version if pkg.installed else None,
            'summary': version.summary if version else '', 'description': version.description if version else '',
            'homepage': version.homepage if version else '', 'installed_size': version.installed_size if version else 0,
            'download_size': version.size if version else 0,
            'ubuntu_candidate': trusted(pkg.candidate),
            'origins': [{'origin': o.origin, 'archive': o.archive, 'component': o.component, 'site': o.site, 'trusted': o.trusted} for o in (version.origins if version else [])]}


def plan(cache, name):
    if name not in cache:
        raise ValueError('Package is not present in configured APT indexes. Refresh package metadata if necessary.')
    pkg = cache[name]
    if not trusted(pkg.candidate):
        raise ValueError('Installation requires an authenticated Ubuntu repository candidate')
    cache.clear()
    pkg.mark_install(auto_fix=True, auto_inst=True, from_user=True)
    changes = cache.get_changes()
    if any(p.marked_delete for p in changes):
        raise ValueError('Installation would remove packages; no changes were made')
    if any(not trusted(p.candidate) for p in changes):
        raise ValueError('All dependencies must have authenticated Ubuntu candidates')
    versions = sorted([{'package': p.name, 'version': p.candidate.version} for p in changes], key=lambda p: p['package'])
    return {'package': name, 'version': pkg.candidate.version, 'changes': versions,
            'download_bytes': cache.required_download, 'disk_delta_bytes': cache.required_space,
            'already_installed': bool(pkg.installed and pkg.installed.version == pkg.candidate.version),
            'sha256': hashlib.sha256(json.dumps(versions, sort_keys=True).encode()).hexdigest()}


def documents(name):
    files = run(['/usr/bin/dpkg-query', '-L', name]).splitlines()
    docs, binaries = [], []
    total = 0
    for entry in files:
        path = pathlib.Path(entry)
        if entry.startswith(('/usr/bin/', '/usr/sbin/', '/bin/', '/sbin/')) and path.is_file():
            binaries.append(entry)
        if not entry.startswith(('/usr/share/doc/', '/usr/share/man/')) or not path.is_file():
            continue
        real = path.resolve()
        if not str(real).startswith(('/usr/share/doc/', '/usr/share/man/')) or real.stat().st_uid != 0 or real.stat().st_mode & 0o022:
            continue
        if len(docs) >= 16 or total >= 120000:
            break
        if path.suffix in ('.png', '.pdf', '.svg', '.jpg', '.zip', '.xz', '.bz2'):
            continue
        try:
            opener = gzip.open if path.suffix == '.gz' else open
            with opener(real, 'rb') as handle:
                data = handle.read(min(24000, 120000-total))
            if b'\x00' in data:
                continue
            text = data.decode('utf-8', 'replace'); total += len(text)
            docs.append({'path': entry, 'text': text, 'sha256': hashlib.sha256(data).hexdigest()})
        except (OSError, EOFError):
            continue
    return {'package': name, 'binaries': sorted(set(binaries)), 'documents': docs,
            'note': 'Installed documentation is reference data; it does not activate executable adapters.'}


def repository_sources(directory=pathlib.Path('/etc/apt')):
    paths = [directory / 'sources.list'] + sorted((directory / 'sources.list.d').glob('*.list')) + sorted((directory / 'sources.list.d').glob('*.sources'))
    rows = []
    for path in paths:
        if not path.is_file() or path.stat().st_size > 1000000:
            continue
        text = path.read_text(errors='replace')
        entries = []
        if path.suffix == '.sources':
            for paragraph in re.split(r'\n\s*\n', text):
                fields = {}
                for line in paragraph.splitlines():
                    if ':' in line and not line.startswith((' ', '#')):
                        key, value = line.split(':', 1);fields[key.lower()] = value.strip()
                if fields.get('enabled', 'yes').lower() == 'no':
                    continue
                for uri in fields.get('uris', '').split():
                    entries.append((uri, fields.get('suites', ''), fields.get('components', ''), fields.get('types', 'deb')))
        else:
            for line in text.splitlines():
                match = re.match(r'^\s*(deb(?:-src)?)\s+(?:\[[^]]*\]\s+)?(\S+)\s+(\S+)(?:\s+([^#]+))?', line)
                if match:
                    entries.append((match[2], match[3], (match[4] or '').strip(), match[1]))
        for index, (uri, suites, components, types) in enumerate(entries):
            parsed = urlsplit(uri)
            # Credentials, query strings and fragments never enter watcher events.
            host = parsed.hostname or ''
            if ':' in host:
                host = '[' + host + ']'
            if parsed.port:
                host += ':' + str(parsed.port)
            clean = urlunsplit((parsed.scheme, host, parsed.path, '', ''))
            identity = hashlib.sha256(json.dumps([clean, suites, types]).encode()).hexdigest()
            rows.append({'identity': identity, 'file': str(path.relative_to(directory)), 'source': clean,
                         'suites': suites, 'components': components, 'types': types})
    return {'sources': rows}


def execute(request):
    operation, value = validate(request)
    release = ubuntu()
    if operation == 'status':
        return {'os': release.get('PRETTY_NAME'), 'repository': 'configured Ubuntu APT sources',
                'operations': sorted(OPERATIONS), 'privileged_helper': True}
    if operation == 'sources':
        return repository_sources()
    if operation == 'refresh':
        return {'status': 'refreshed', 'output': run(['/usr/bin/apt-get', 'update', '-o', 'APT::Update::Error-Mode=any'], timeout=900)}
    import apt
    import apt_pkg
    apt_pkg.config.set("APT::Install-Recommends", "false")
    cache = apt.Cache()
    if operation in ('search', 'catalog'):
        words = value.lower().split()
        rows = []
        for pkg in cache:
            candidate = pkg.candidate
            if candidate and trusted(candidate) and all(word in (pkg.name + ' ' + candidate.summary).lower() for word in words):
                rows.append({'package': pkg.name, 'summary': candidate.summary, 'version': candidate.version})
            if len(rows) > (1000 if operation == 'catalog' else 40):
                break
        limit = 1000 if operation == 'catalog' else 40
        return {'query': value, 'packages': rows[:limit], 'limit': limit, 'complete': len(rows) <= limit}
    if value not in cache:
        raise ValueError('Package is absent from configured APT indexes')
    if operation == 'show':
        return metadata(cache[value])
    if operation == 'docs':
        if not cache[value].is_installed:
            raise ValueError('Install the package before importing its local documentation')
        return documents(value)
    result = plan(cache, value)
    if operation == 'plan':
        return result
    if operation == 'install':
        if result['already_installed']:
            return dict(result, status='installed', verified=True)
        # --no-remove fails closed on unexpected dependency removal; default APT
        # archive authentication remains enabled. No new repositories are added.
        argv = ['/usr/bin/apt-get', '--assume-yes', '--no-remove', '--no-install-recommends',
                '-o', 'DPkg::Lock::Timeout=60', 'install', value + '=' + result['version']]
        output = run(argv, timeout=1800)
        cache.open(None)
        installed = cache[value].installed
        if not installed or installed.version != result['version']:
            raise ValueError('Installed package version did not match the verified candidate')
        return dict(result, status='installed', verified=True, output=output)
    raise ValueError('Unsupported package operation')


def main():
    if os.geteuid() != 0:
        raise ValueError('Package helper requires its installed sudo rule')
    os.environ.clear()
    os.environ.update(ENV)
    os.chdir('/')
    raw = sys.stdin.buffer.read(16385)
    if len(raw) > 16384:
        raise ValueError('Package request is too large')
    request = json.loads(raw)
    validate(request)
    # Serialize this helper's package operations; APT also retains its own locks.
    lock = os.open('/run/lock/lightek-package-control.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(lock, 'w') as handle:
        deadline = time.monotonic() + 120
        while True:
            try:
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise ValueError('Another package operation is still running; retry after it completes')
                time.sleep(0.25)
        result = execute(request)
    print(json.dumps(result))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(json.dumps({'error': str(error)}))
        sys.exit(1)
