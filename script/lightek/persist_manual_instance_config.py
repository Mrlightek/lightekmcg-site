"""Persist only the nonsecret VPS settings selected by the catalog preflight."""
import json
import os
import pathlib
import re
import shlex
import shutil
import tempfile

def persist(source, target):
    values = json.loads(source.read_text())
    allowed = {'LIGHTEK_AUTO_VPS_MONTHLY_COST_CENTS', 'LIGHTEK_AUTO_VPS_REGION',
               'LIGHTEK_AUTO_VPS_PLAN', 'LIGHTEK_AUTO_VPS_IMAGE'}
    if set(values) != allowed or not all(isinstance(v, str) and re.fullmatch(r'[a-zA-Z0-9/_.:-]+', v) for v in values.values()):
        raise RuntimeError('Invalid VPS deployment settings')
    backup = target.with_name(target.name + '.before-manual-paid-instance')
    if not backup.exists():
        shutil.copy2(target, backup)
    info = target.stat()
    lines = [line for line in target.read_text().splitlines()
             if not re.match(r'^\s*(?:export\s+)?(?:' + '|'.join(sorted(allowed)) + r')\s*=', line)]
    lines += [key + '=' + shlex.quote(value) for key, value in sorted(values.items())]
    rendered = '\n'.join(lines) + '\n'
    if rendered == target.read_text():
        print('VPS_DEPLOYMENT_SETTINGS_UNCHANGED')
        return False
    fd, name = tempfile.mkstemp(dir=target.parent, prefix='.paid-instance-env-')
    try:
        os.fchmod(fd, info.st_mode & 0o777)
        os.fchown(fd, info.st_uid, info.st_gid)
        with os.fdopen(fd, 'w') as stream:
            stream.write(rendered)
        os.replace(name, target)
    finally:
        pathlib.Path(name).unlink(missing_ok=True)
    print('VPS_DEPLOYMENT_SETTINGS_PERSISTED')
    return True


if __name__ == "__main__":
    persist(pathlib.Path("/var/www/lightekmcg-site/tmp/manual_paid_vps_config.json"),
            pathlib.Path("/etc/lightek/lightekmcg-site.env"))
