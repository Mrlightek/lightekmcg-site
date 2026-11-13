"""Managed Ubuntu AD/Samba AD membership. JSON stdin; no password arguments/logs."""
import fcntl
import configparser
import json
import os
from pathlib import Path
import re
import subprocess
import sys

def run(argv, secret=None):
    result = subprocess.run(argv, input=secret, text=True, capture_output=True, timeout=360, check=False)
    if result.returncode:
        raise RuntimeError("directory command failed")
    return result.stdout

def apply_locked(payload, root=Path('/'), runner=run):
    realm = str(payload.get('realm', ''))
    binding = payload.get('binding_id')
    principals = payload.get('principals', [])
    revision = payload.get('revision')
    if not isinstance(revision,int) or revision < 0:
        raise ValueError('invalid policy revision')
    enabled = payload.get('enabled') is True
    if not enabled and principals:
        raise ValueError('disabled realm cannot permit principals')
    if not re.fullmatch(r'[a-z0-9](?:[a-z0-9.-]{0,250}[a-z0-9])?\.[a-z]{2,}', realm) or not isinstance(binding, int) or binding <= 0:
        raise ValueError('invalid realm binding')
    if not isinstance(principals, list) or len(principals) > 5000:
        raise ValueError('invalid directory allowlist')
    if any(not isinstance(p, str) or not re.fullmatch(r'[A-Za-z0-9._-]+@' + re.escape(realm), p, re.I) for p in principals):
        raise ValueError('invalid directory principal')
    action = payload.get('action')
    if action not in ('sync', 'join'):
        raise ValueError('unknown action')
    marker = root / 'var/lib/lightek/directory/binding.json'
    saved = json.loads(marker.read_text()) if marker.exists() else {}
    if saved and (saved.get('realm') != realm or saved.get('binding_id') != binding):
        raise ValueError('unmanaged directory binding')
    if saved.get('revision',-1) > revision:
        return {'status':'stale','realm':realm,'binding_id':binding,'revision':saved['revision']}
    existing = runner(['realm', 'list', '--name-only']).strip().splitlines() if (root / 'usr/sbin/realm').exists() or (root / 'usr/bin/realm').exists() else []
    if existing and (existing != [realm] or not marker.exists() or saved.get('realm') != realm or saved.get('binding_id') != binding):
        raise ValueError('refusing to change an unmanaged domain membership')
    if not existing:
        write_marker(marker,{'realm':realm,'binding_id':binding,'revision':revision,'verified':False})
        if not enabled:
            return {'status':'succeeded','realm':realm,'binding_id':binding,'principal_count':0,'joined':False}
        if action == 'sync':
            return {'status': 'needs_join', 'realm': realm, 'binding_id': binding}
        username, password = payload.get('join_user',''), payload.get('join_password','')
        if not re.fullmatch(r'[A-Za-z0-9._@-]{1,200}', username) or not isinstance(password,str) or not password or '\n' in password or '\r' in password:
            raise ValueError('invalid join credential')
        runner(['apt-get', 'update'])
        runner(['apt-get', 'install', '-y', 'realmd', 'sssd-ad', 'sssd-tools', 'adcli', 'libnss-sss', 'libpam-sss', 'samba-common-bin'])
        marker.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
        write_marker(marker,{'realm':realm,'binding_id':binding,'revision':revision,'verified':False})
        try:
            runner(['realm', 'join', '--client-software=sssd', '--membership-software=adcli', '--user='+username, realm], password+'\n')
        finally:
            # Fail closed even if joining partially succeeded. Never permit all AD users.
            try:
                runner(['realm','deny','--all','--realm='+realm])
            except Exception:
                runner(['systemctl','stop','sssd'])
                raise
    if existing and saved.get('verified') and saved.get('principals') == sorted(set(principals)):
        runner(['adcli','testjoin','--domain='+realm])
        write_marker(marker,{'realm':realm,'binding_id':binding,'revision':revision,'verified':True,'principals':sorted(set(principals))})
        return {'status':'succeeded','realm':realm,'binding_id':binding,'principal_count':len(set(principals)),'joined':True}
    runner(['realm','deny','--all','--realm='+realm])
    config_path = root / 'etc/sssd/sssd.conf'
    config = configparser.ConfigParser(interpolation=None)
    config.read(config_path)
    section = 'domain/'+realm
    if section not in config:
        raise RuntimeError('SSSD realm configuration missing')
    config[section]['cache_credentials'] = 'false'
    with config_path.open('w') as stream:
        config.write(stream)
    config_path.chmod(0o600)
    if principals:
        runner(['realm','permit','--realm='+realm,'-u']+principals)
    runner(['sss_cache','-E'])
    runner(['systemctl','restart','sssd'])
    runner(['adcli','testjoin','--domain='+realm])
    write_marker(marker,{'realm':realm,'binding_id':binding,'revision':revision,'verified':True,'principals':sorted(set(principals))})
    return {'status':'succeeded','realm':realm,'binding_id':binding,'principal_count':len(set(principals)),'joined':True}

def write_marker(path,value):
    path.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
    temporary=path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value))
    temporary.chmod(0o600)
    os.replace(temporary,path)

def apply(payload, root=Path('/'), runner=run):
    directory=root / 'var/lib/lightek/directory'
    directory.mkdir(parents=True,exist_ok=True,mode=0o700)
    if directory.is_symlink():
        raise ValueError('unsafe directory state path')
    with (directory / 'policy.lock').open('a') as lock:
        os.chmod(lock.name,0o600)
        fcntl.flock(lock,fcntl.LOCK_EX)
        return apply_locked(payload,root,runner)

def main():
    os.environ['DEBIAN_FRONTEND'] = 'noninteractive'
    try:
        if os.geteuid() != 0:
            raise PermissionError('root helper required')
        payload = json.loads(sys.stdin.read(65537))
        print(json.dumps(apply(payload)))
    except Exception as error:
        print(json.dumps({'status':'failed','error_class':type(error).__name__}))
        return 1
    return 0
if __name__ == '__main__':
    sys.exit(main())
