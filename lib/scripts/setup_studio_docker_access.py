#!/usr/bin/env python3
"""Root deployment prerequisite: local Docker access for the actual worker account."""
import argparse
import grp
import os
import pwd
import shutil
import stat
import subprocess
from pathlib import Path

SOCKET=Path('/var/run/docker.sock')
CLEAN_ENV=['env','-u','DOCKER_CONTEXT','-u','DOCKER_TLS_VERIFY','-u','DOCKER_CERT_PATH','DOCKER_HOST=unix:///var/run/docker.sock']

def command(args):
    return subprocess.run(args,capture_output=True,text=True,timeout=240)

def checked(args,run):
    result=run(args)
    if result.returncode:
        raise RuntimeError('Docker prerequisite failed: '+str(result.stderr or '').strip()[-1200:])
    return result

def prepare(user,run=command):
    pwd.getpwnam(user)  # Never create an account on a misspelled deployment profile.
    if not shutil.which('docker'):
        checked(['apt-get','update','-qq'],run)
        checked(['apt-get','install','-y','--no-install-recommends','docker.io'],run)
    if run(['getent','group','docker']).returncode:
        checked(['groupadd','--system','docker'],run)
    checked(['systemctl','enable','--now','docker'],run)
    checked([*CLEAN_ENV,'docker','info'],run)
    info=SOCKET.stat()
    if not stat.S_ISSOCK(info.st_mode) or info.st_uid!=0:
        raise RuntimeError('Expected the root-owned local Docker socket at '+str(SOCKET))
    if info.st_gid==0:
        raise RuntimeError('The local Docker socket belongs to group root; configure the Docker daemon socket group before granting worker access')
    group=grp.getgrgid(info.st_gid).gr_name
    os.chmod(SOCKET,0o660)
    # -a preserves www-data and every existing supplemental group.
    checked(['usermod','-a','-G',group,user],run)
    # A fresh process is essential: changing /etc/group does not update a running shell.
    checked(['runuser','-u',user,'--',*CLEAN_ENV,'docker','info'],run)
    return group

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--app-user',required=True);args=parser.parse_args()
    if os.geteuid()!=0:raise SystemExit('Run Docker access setup from the root deployment pipeline')
    group=prepare(args.app_user)
    print('LIGHTEK_STUDIO_DOCKER_ACCESS_READY='+args.app_user+' group='+group)
if __name__=='__main__':
    try:main()
    except Exception as error:raise SystemExit(str(error))
