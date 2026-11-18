#!/usr/bin/env python3
"""Managed Genesis runtime: trusted package catalog, JSON stdin, bounded receipts."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

ROOT = Path('/opt/lightek/genesis')
CATALOG_PATH = Path('/usr/local/lib/lightek/studio-ai-packages.json')


def catalog():
    return globals().get('_LIGHTEK_AI_CATALOG') or json.loads(CATALOG_PATH.read_text())


def run(*args, timeout=1800, capture=False):
    result = subprocess.run(args, check=True, stdout=subprocess.PIPE if capture else subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, timeout=timeout, text=True)
    return result.stdout.strip() if capture else None


def identity(payload):
    for key in ('domain', 'owner_domain'):
        if not re.fullmatch(r'[a-z0-9](?:[a-z0-9.-]{1,251})[a-z0-9]', payload[key]) or '.' not in payload[key]:
            raise ValueError('invalid_identity')
    if not re.fullmatch(r'[a-zA-Z0-9_-]{8,100}', payload['request_id']):
        raise ValueError('invalid_identity')


def atomic(path, data):
    descriptor, temporary = tempfile.mkstemp(dir=path.parent, prefix='.genesis-')
    try:
        with os.fdopen(descriptor, 'w') as output:
            json.dump(data, output)
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)


def status(payload):
    identity(payload)
    state = ROOT / 'state.json'
    if not state.is_file(): return {'status': 'not_installed'}
    result = json.loads(state.read_text())
    if result['owner_domain'] != payload['owner_domain'] or result['domain'] != payload['domain']:
        raise ValueError('worker_assigned_elsewhere')
    return result if result.get('request_id') == payload['request_id'] else {'status': 'starting'}


def resources(package, device, memory_mib, available_mib, disk_bytes, gpu_mib=0, nvidia_runtime=False):
    if device not in package['devices']: raise ValueError('gpu_required')
    minimum = package['ram_gib'] * 1024
    if memory_mib < minimum or available_mib < minimum - 2048: raise ValueError('insufficient_memory')
    if disk_bytes < package['free_disk_gib'] * 1024**3: raise ValueError('insufficient_disk')
    if device == 'cuda' and not nvidia_runtime: raise ValueError('gpu_unavailable')
    if device == 'cuda' and gpu_mib < package['vram_mib']: raise ValueError('insufficient_vram')


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise ValueError('unexpected_engine_redirect')


class HTTPSRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not newurl.startswith('https://'): raise ValueError('unsafe_download_redirect')
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def checksum(path):
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(8*1024*1024), b''): digest.update(chunk)
    return digest.hexdigest()


def download(model, folder, progress, opener=None):
    destination = folder / model['name']
    if destination.is_symlink(): raise ValueError('unsafe_model_path')
    if destination.exists() and destination.stat().st_size == model['bytes'] and checksum(destination) == model['sha256']:
        return
    partial = folder / (model['name'] + '.part')
    if partial.is_symlink(): raise ValueError('unsafe_model_path')
    offset = partial.stat().st_size if partial.exists() else 0
    if offset > model['bytes']: partial.unlink(); offset = 0
    url = f"https://huggingface.co/{model['repo']}/resolve/{model['revision']}/{model['path']}"
    headers = {'User-Agent': 'LightekGenesis/1.0'}
    if offset: headers['Range'] = f'bytes={offset}-'
    opener = opener or urllib.request.build_opener(HTTPSRedirect())
    if offset != model['bytes']:
        with opener.open(urllib.request.Request(url, headers=headers), timeout=60) as response:
            if offset and response.status == 206:
                if not response.headers.get('Content-Range', '').startswith(f'bytes {offset}-'): raise ValueError('invalid_download_range')
            elif response.status == 200: offset = 0
            else: raise ValueError('model_download_failed')
            with partial.open('ab' if offset else 'wb') as output:
                while True:
                    chunk = response.read(8*1024*1024)
                    if not chunk: break
                    offset += len(chunk)
                    if offset > model['bytes']: raise ValueError('model_size_mismatch')
                    output.write(chunk)
                    progress('downloading_model', model=model['name'], downloaded_bytes=offset, total_bytes=model['bytes'])
    progress('verifying_model', model=model['name'], downloaded_bytes=offset, total_bytes=model['bytes'])
    if partial.stat().st_size != model['bytes'] or checksum(partial) != model['sha256']:
        partial.unlink(missing_ok=True)
        raise ValueError('model_checksum_mismatch')
    partial.chmod(0o644)
    os.replace(partial, destination)


def dockerfile(config, device):
    commit = config['engine_commit']
    if not re.fullmatch('[a-f0-9]{40}', commit): raise ValueError('invalid_engine_version')
    index = 'cpu' if device == 'cpu' else 'cu126'
    return f'''FROM python:3.12-slim-bookworm
RUN apt-get update && apt-get install -y --no-install-recommends git ffmpeg libglib2.0-0 libgl1 && rm -rf /var/lib/apt/lists/*
RUN git init /opt/ComfyUI && cd /opt/ComfyUI && git remote add origin https://github.com/Comfy-Org/ComfyUI.git && git fetch --depth=1 origin {commit} && git checkout --detach FETCH_HEAD && test "$(git rev-parse HEAD)" = "{commit}"
RUN pip install --no-cache-dir torch==2.7.1 torchvision==0.22.1 torchaudio==2.7.1 --index-url https://download.pytorch.org/whl/{index}
RUN pip install --no-cache-dir -r /opt/ComfyUI/requirements.txt && pip freeze > /opt/lightek-genesis-requirements.txt
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 HF_HUB_DISABLE_TELEMETRY=1 DO_NOT_TRACK=1
WORKDIR /opt/ComfyUI
USER 10001:10001
'''


def compose(config, device, memory_gib):
    command = ['python', 'main.py', '--listen', '0.0.0.0', '--port', '8188', '--disable-api-nodes', '--disable-all-custom-nodes',
               '--base-directory', '/data', '--output-directory', '/data/output', '--temp-directory', '/data/temp',
               '--input-directory', '/data/input', '--user-directory', '/data/user']
    command += ['--cpu'] if device == 'cpu' else ['--lowvram']
    service = {'image': f"lightek/genesis:{config['engine_commit'][:12]}-{device}", 'restart': 'unless-stopped',
        'user': '10001:10001', 'read_only': True, 'cap_drop': ['ALL'], 'security_opt': ['no-new-privileges:true'],
        'pids_limit': 512, 'mem_limit': f'{memory_gib}g', 'cpus': max(1, min(8, (os.cpu_count() or 2)-1)),
        'ports': ['127.0.0.1:8188:8188'], 'tmpfs': ['/tmp:rw,nosuid,nodev,size=512m'],
        'volumes': [str(ROOT / 'models')+':/data/models:ro'] + [str(ROOT / name)+':/data/'+name+':rw' for name in ('output','input','user','temp')],
        'command': command, 'logging': {'driver':'json-file','options':{'max-size':'10m','max-file':'3'}}}
    if device == 'cuda': service['deploy']={'resources':{'reservations':{'devices':[{'driver':'nvidia','count':1,'capabilities':['gpu']}]}}}
    return {'services': {'genesis': service}}


def patch_vhost(text, domain, token):
    if len(re.findall(r'<VirtualHost\b', text, re.I)) != 1 or not re.search(r'<VirtualHost\s+[^>]*:443\s*>', text, re.I): raise ValueError('https_vhost_required')
    if not re.search(r'^\s*ServerName\s+'+re.escape(domain)+r'\s*$', text, re.M): raise ValueError('https_vhost_required')
    if not re.fullmatch('[a-f0-9]{64}', token): raise ValueError('invalid_credential')
    # A repeated install replaces only this managed block, preserving the site.
    text = re.sub(r'\n\s*# LIGHTEK GENESIS BEGIN.*?# LIGHTEK GENESIS END\n', '\n', text, flags=re.S)
    block = f'''\n  # LIGHTEK GENESIS BEGIN
  <Location "/lightek-ai/">
    Require expr "%{{HTTP:Authorization}} == 'Bearer {token}'"
  </Location>
  ProxyPass "/lightek-ai/" "http://127.0.0.1:8188/" connectiontimeout=5 timeout=120
  ProxyPassReverse "/lightek-ai/" "http://127.0.0.1:8188/"
  # LIGHTEK GENESIS END
'''
    # Put the specific proxy before any catch-all ProxyPass rule.
    match = re.search(r'^\s*ProxyPass\s|</VirtualHost>', text, re.M | re.I)
    return text[:match.start()] + block + text[match.start():]


def apply(payload):
    identity(payload)
    if payload.get('action') == 'status': return status(payload)
    if payload.get('action') != 'install' or os.geteuid() != 0: raise ValueError('managed_root_required')
    config = catalog()
    package = config['packages'].get(payload.get('package_id'))
    if not package: raise ValueError('unknown_package')
    device = payload.get('device')
    mem = dict(re.findall(r'^(MemTotal|MemAvailable):\s+(\d+)', Path('/proc/meminfo').read_text(), re.M))
    gpu = run('nvidia-smi','--query-gpu=memory.total','--format=csv,noheader,nounits',capture=True,timeout=10) if device=='cuda' and shutil.which('nvidia-smi') else ''
    runtimes = run('docker','info','--format','{{json .Runtimes}}',capture=True,timeout=15) if device=='cuda' and shutil.which('docker') else ''
    resources(package,device,int(mem['MemTotal'])//1024,int(mem['MemAvailable'])//1024,shutil.disk_usage('/opt').free,
              min([int(v) for v in gpu.splitlines()] or [0]), 'nvidia' in runtimes)
    if not re.fullmatch('[a-f0-9]{64}',payload.get('api_token','')): raise ValueError('invalid_credential')
    for path in [ROOT.parent,ROOT]:
        if path.is_symlink(): raise ValueError('unsafe_runtime_path')
        path.mkdir(parents=True,exist_ok=True);os.chown(path,0,0);path.chmod(0o700 if path==ROOT else 0o755)
    with (ROOT / 'install.lock').open('a') as lock:
        try: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError: raise ValueError('installation_busy')
        state_path = ROOT / 'state.json'
        old = json.loads(state_path.read_text()) if state_path.exists() else {}
        if old and (old['owner_domain'] != payload['owner_domain'] or old['domain'] != payload['domain']): raise ValueError('worker_assigned_elsewhere')
        state = {k:payload[k] for k in ('domain','owner_domain','request_id','package_id','device')}
        def progress(phase,**values):
            state.update(status='running',phase=phase,**values);atomic(state_path,state)
        progress('checking_runtime')
        vhosts=[p.resolve() for p in Path('/etc/apache2/sites-enabled').glob('*.conf') if re.search(r'^\s*ServerName\s+'+re.escape(payload['domain'])+r'\s*$',p.read_text(),re.M) and ':443' in p.read_text()]
        if len(vhosts)!=1: raise ValueError('https_vhost_required')
        vhost=vhosts[0];original_mode=vhost.stat().st_mode & 0o777;original=vhost.read_text();updated=patch_vhost(original,payload['domain'],payload['api_token'])
        for name in ('models','input','output','user','temp'):
            path=ROOT/name
            if path.is_symlink(): raise ValueError('unsafe_runtime_path')
            path.mkdir(exist_ok=True);path.chmod(0o755)
            if name!='models': os.chown(path,10001,10001)
        if not shutil.which('docker'):
            run('apt-get','update','-qq');run('apt-get','install','-y','docker.io','docker-compose-v2')
        run('systemctl','enable','--now','docker')
        progress('building_engine')
        with tempfile.TemporaryDirectory(prefix='genesis-build-') as temporary:
            Path(temporary,'Dockerfile').write_text(dockerfile(config,device))
            image=compose(config,device,6)['services']['genesis']['image']
            run('docker','build','-t',image,temporary,timeout=2400)
        if device=='cuda': run('docker','run','--rm','--gpus','all',image,'python','-c','import torch; assert torch.cuda.is_available()',timeout=60)
        for model in config['models']:
            if model['id'] not in package['models']: continue
            folder=ROOT/'models'/model['folder'];folder.mkdir(exist_ok=True);folder.chmod(0o755)
            download(model,folder,progress)
        progress('starting_engine')
        definition=compose(config,device,package['ram_gib']-2)
        compose_path=ROOT/'compose.json';atomic(compose_path,definition)
        run('docker','compose','-p','lightek-genesis','-f',str(compose_path),'up','-d',timeout=120)
        run('a2enmod','proxy','proxy_http','authz_core')
        vhost.chmod(0o600)  # Root reads Apache configuration before dropping privileges.
        vhost.write_text(updated)
        try:
            run('apache2ctl','configtest',timeout=20);run('systemctl','reload','apache2',timeout=30)
        except Exception:
            vhost.write_text(original);vhost.chmod(original_mode);run('apache2ctl','configtest',timeout=20);raise
        progress('verifying_engine')
        url='https://'+payload['domain']+'/lightek-ai/object_info'
        for attempt in range(45):
            try:
                request=urllib.request.Request(url,headers={'Authorization':'Bearer '+payload['api_token']})
                with urllib.request.build_opener(NoRedirect()).open(request,timeout=10) as response: nodes=json.loads(response.read(5*1024*1024+1))
                if not isinstance(nodes,dict) or 'KSampler' not in nodes: raise ValueError('invalid_engine_inventory')
                state.update(status='ready',phase='ready',engine_commit=config['engine_commit'],engine_version=config['engine_version'],
                             models=[m['name'] for m in config['models'] if m['id'] in package['models']],readiness='engine_and_model_files')
                atomic(state_path,state);return state
            except Exception:
                if attempt==44: raise ValueError('engine_health_failed')
                time.sleep(2)


if __name__ == '__main__':
    try:
        print(json.dumps(apply(json.load(sys.stdin))))
    except Exception as error:
        print(json.dumps({'status':'failed','reason':str(error) if isinstance(error,ValueError) else 'installation_failed','error_class':type(error).__name__}))
        sys.exit(1)
