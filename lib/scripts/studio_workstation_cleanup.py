#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import time


def cleanup(root, now=None, command=subprocess.run):
    now=int(time.time()) if now is None else now
    for directory in (root/'sessions').glob('*'):
        if directory.is_symlink() or not re.fullmatch(r'[a-f0-9]{32}',directory.name):continue
        manifest=directory/'session.json'
        if manifest.is_symlink():continue
        try:data=json.loads(manifest.read_text())
        except (OSError,ValueError):continue
        if data.get('session_key')!=directory.name or data.get('expires_at',now+1)>now:continue
        container=data.get('container_id','')
        if re.fullmatch(r'[a-f0-9]{64}',container or ''):
            result=command(['docker','inspect','--format','{{index .Config.Labels "lightek.workstation.session"}}',container],capture_output=True,text=True,timeout=10)
            if result.returncode==0 and result.stdout.strip()==directory.name:
                command(['docker','rm','-f',container],check=True,capture_output=True,timeout=15)
        data.update(status='expired',port=None)
        temporary=directory/'session.json.tmp';temporary.write_text(json.dumps(data));temporary.replace(manifest)
        work=directory/'work'
        if data['expires_at']+86400<now and work.exists() and not work.is_symlink():shutil.rmtree(work)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,required=True);args=parser.parse_args();cleanup(args.root)
