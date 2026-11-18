#!/usr/bin/env python3
"""Run real pinned ComfyUI + MCP + Rails/Blender/FFmpeg proof on loopback."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
import psutil

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--comfy-root',required=True)
parser.add_argument('--comfy-python',default=sys.executable)
parser.add_argument('ruby_command',nargs=argparse.REMAINDER)
args=parser.parse_args()
command=args.ruby_command
if command and command[0]=='--': command=command[1:]
if not command: parser.error('Pass the Ruby test command after --')
repo=Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='lightek-comfy-proof-') as directory:
    root=Path(directory)
    for folder in ('custom_nodes','input','output','temp','user'): (root/folder).mkdir()
    shutil.copytree(repo/'lib/comfyui/lightek_studio',root/'custom_nodes/lightek_studio')
    env=os.environ|{'LIGHTEK_STUDIO_ORIGIN':'http://127.0.0.1:18466','STUDIO_COMFY_PROOF_URL':'http://127.0.0.1:18188'}
    log=root/'comfy.log'
    with log.open('w') as output:
        process=subprocess.Popen([args.comfy_python,str(Path(args.comfy_root)/'main.py'),'--cpu','--listen','127.0.0.1','--port','18188',
            '--disable-api-nodes','--disable-all-custom-nodes','--whitelist-custom-nodes','lightek_studio',
            '--base-directory',str(root),'--user-directory',str(root/'user'),'--output-directory',str(root/'output'),
            '--input-directory',str(root/'input'),'--temp-directory',str(root/'temp'),
            '--database-url','sqlite:///'+str(root/'user/comfy.db')],env=env,stdout=output,stderr=subprocess.STDOUT)
        peak=[0];stopped=threading.Event()
        def measure():
            while not stopped.wait(.1):
                try: peak[0]=max(peak[0],psutil.Process(process.pid).memory_info().rss)
                except psutil.Error: return
        thread=threading.Thread(target=measure,daemon=True);thread.start()
        try:
            opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
            for attempt in range(120):
                if process.poll() is not None: raise RuntimeError('ComfyUI exited during startup')
                try:
                    with opener.open(env['STUDIO_COMFY_PROOF_URL']+'/object_info/LightekStudioJob',timeout=2) as response:
                        nodes=json.load(response)
                    if 'LightekStudioJob' in nodes: break
                except OSError: pass
                time.sleep(.5)
            else: raise RuntimeError('ComfyUI workflow nodes did not become ready')
            result=subprocess.run(command,cwd=repo,env=env,timeout=150)
            print(json.dumps({'check':'real_comfy_mcp_workflow','exit_code':result.returncode,'comfy_peak_rss_mib':round(peak[0]/1024**2,1)}),flush=True)
            if result.returncode: print(log.read_text()[-10000:],file=sys.stderr)
            sys.exit(result.returncode)
        except Exception:
            print(log.read_text()[-10000:],file=sys.stderr)
            raise
        finally:
            stopped.set();thread.join()
            process.terminate()
            try: process.wait(timeout=10)
            except subprocess.TimeoutExpired: process.kill();process.wait()
