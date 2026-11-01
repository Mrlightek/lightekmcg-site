#!/usr/bin/env python3
"""Idempotent per-installation streaming runtime. Invoked by provisioning/deploy/fleet."""
import argparse,hashlib,ipaddress,json,os,pathlib,pwd,re,secrets,shlex,subprocess,time,urllib.request

def run(args):subprocess.run(args,check=True,timeout=900)
def plan(root,user,domain,previous=None,environment=None):
    previous=previous or {};environment=environment or {};root=pathlib.Path(root).absolute()
    if not re.fullmatch(r'[a-zA-Z0-9_.-]+',user) or not re.fullmatch(r'[a-zA-Z0-9.-]+',domain):raise ValueError('Invalid installation identity')
    key=hashlib.sha256(str(root).encode()).hexdigest()[:12];base=pathlib.Path('/var/lib/lightek-spatial')/key
    def value(name,default):return environment.get(name) or previous.get(name) or default
    port=int(value('STUDIO_SPATIAL_PORT',18000+int(key[:4],16)%1000))
    if not 1024<=port<=65535:raise ValueError('Invalid streaming port')
    config={
      'STUDIO_SPATIAL_ROOT':str(base/'sessions'),'STUDIO_SPATIAL_SECRET':value('STUDIO_SPATIAL_SECRET',secrets.token_hex(32)),
      'STUDIO_SPATIAL_URL':f'http://127.0.0.1:{port}','STUDIO_SPATIAL_PORT':str(port),
      'SPATIAL_CONTAINER_IMAGE':value('SPATIAL_CONTAINER_IMAGE',environment.get('STUDIO_RENDER_WORKER_IMAGE') or environment.get('STUDIO_ASSET_WORKER_IMAGE') or 'lightek/studio-media:20261101'),
      'SPATIAL_BACKEND':value('SPATIAL_BACKEND','render'),'SPATIAL_RENDER_ENGINE':value('SPATIAL_RENDER_ENGINE','CYCLES'),
      'SPATIAL_ENCODER':value('SPATIAL_ENCODER','libx264'),'SPATIAL_WIDTH':value('SPATIAL_WIDTH','640'),'SPATIAL_HEIGHT':value('SPATIAL_HEIGHT','360'),'SPATIAL_FPS':value('SPATIAL_FPS','60'),
      'SPATIAL_MAX_SESSIONS':value('SPATIAL_MAX_SESSIONS','2'),'SPATIAL_ORIGINS':json.dumps([f'https://{domain}']),
      'SPATIAL_COMMIT_URL':f'https://{domain}/internal/studio/spatial/commit',
      'SPATIAL_TURN_SECRET':value('SPATIAL_TURN_SECRET',secrets.token_hex(32)),'SPATIAL_TURN_HOST':domain,
      'STUDIO_SPATIAL_PYTHON':str(base/'venv/bin/python')}
    for name in ['DISPLAY','SPATIAL_XAUTHORITY','SPATIAL_VIEWPORT_SHADING','SPATIAL_WORKER_MEMORY','SPATIAL_WORKER_CPUS']:
      if value(name,None):config[name]=value(name,None)
    unit=f'''[Unit]
Description=Lightek spatial viewport {key}
After=network.target docker.service coturn.service
[Service]
User={user}
SupplementaryGroups=docker
WorkingDirectory={root}
EnvironmentFile={base}/service.env
ExecStart={base}/venv/bin/python -m services.spatial.server
Restart=on-failure
RestartSec=3
KillMode=control-group
NoNewPrivileges=true
UMask=0077
TimeoutStopSec=20
[Install]
WantedBy=multi-user.target
'''
    proxy=f'ProxyPass "/studio-spatial/ws" "ws://127.0.0.1:{port}/ws" retry=0 timeout=300\nProxyPassReverse "/studio-spatial/ws" "ws://127.0.0.1:{port}/ws"\n'
    return {'key':key,'base':base,'config':config,'unit':unit,'proxy':proxy,'service':f'lightek-spatial-{key}'}
def write(path,content,mode=0o600,owner=None):
    path=pathlib.Path(path);path.parent.mkdir(parents=True,exist_ok=True);temp=path.with_suffix(path.suffix+'.new');
    with os.fdopen(os.open(temp,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600),'w') as output:output.write(content)
    temp.chmod(mode)
    if owner:os.chown(temp,owner.pw_uid,owner.pw_gid)
    temp.replace(path)
def inject_vhosts(text,root,domain,include):
    def replace(match):
        block=match.group()
        if str(root) not in block and not re.search(r'ServerName\s+'+re.escape(domain)+r'(?:\s|$)',block):return block
        line=f'Include "{include}"'
        if line in block:return block
        return block.replace('</VirtualHost>',f'  {line}\n</VirtualHost>')
    return re.sub(r'<VirtualHost\b[^>]*>.*?</VirtualHost>',replace,text,flags=re.S|re.I)
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--app-root',required=True);parser.add_argument('--app-user',required=True);parser.add_argument('--domain',required=True);parser.add_argument('--env-file');args=parser.parse_args()
    if os.geteuid()!=0:raise ValueError('Streaming setup runs as root inside the deployment pipeline')
    os.umask(0o022)  # Runtime libraries are executable by the app; secrets use explicit 0600 writes.
    root=pathlib.Path(args.app_root).absolute();owner=pwd.getpwnam(args.app_user);environment=dict(os.environ)
    if args.env_file:
      values=subprocess.check_output(['bash','-c','set -a; . "$1"; env -0','spatial-env',args.env_file])
      environment.update(dict(item.decode().split('=',1) for item in values.split(b'\0') if b'=' in item))
    turn_config=pathlib.Path('/etc/turnserver.conf')
    if turn_config.exists() and turn_config.read_text().startswith('# LIGHTEK MANAGED SPATIAL TURN'):
      existing=re.search(r'^static-auth-secret=(.+)$',turn_config.read_text(),re.M)
      if existing:environment.setdefault('SPATIAL_TURN_SECRET',existing.group(1))
    runtime=root/'tmp/studio-spatial-runtime.json';previous=json.loads(runtime.read_text()) if runtime.exists() else {}
    setup=plan(root,args.app_user,args.domain,previous,environment);config=setup['config'];base=setup['base'];base.mkdir(parents=True,exist_ok=True)
    # One TURN daemon per server, with independent auth secrets accepted via dynamic realm entries.
    # A customer instance normally has one Rails installation; preserve an existing managed secret.
    turn=pathlib.Path('/etc/turnserver.conf');marker='# LIGHTEK MANAGED SPATIAL TURN\n'
    if turn.exists() and turn.read_text().strip() and not turn.read_text().startswith(marker):
      # Ubuntu's shipped file contains comments only. Never overwrite an operator's live configuration.
      active=[line for line in turn.read_text().splitlines() if line.strip() and not line.lstrip().startswith('#')]
      if active:raise ValueError('Existing TURN configuration needs an explicit external TURN profile; refusing to overwrite it')
    turn_text=marker+'\n'.join(['listening-port=3478','fingerprint','use-auth-secret','static-auth-secret='+config['SPATIAL_TURN_SECRET'],'realm='+args.domain,'min-port=49160','max-port=49200','no-cli','no-multicast-peers','stale-nonce=600','user-quota=12','total-quota=100'])+'\n'
    if not turn.exists() or not turn.read_text().startswith(marker):write(turn,turn_text,0o600)
    installed=subprocess.run(['dpkg-query','-W','-f=${Status}\n','python3-venv','coturn'],capture_output=True,text=True)
    if installed.returncode or installed.stdout.count('install ok installed')!=2:
      run(['apt-get','update','-qq']);run(['apt-get','install','-y','--no-install-recommends','python3-venv','coturn'])
    if not (base/'venv/bin/python').exists():run(['python3','-m','venv',str(base/'venv')])
    dependency_hash=hashlib.sha256((root/'services/spatial/requirements.txt').read_bytes()).hexdigest();receipt=base/'dependencies.sha256'
    if not receipt.exists() or receipt.read_text()!=dependency_hash:
      run([str(base/'venv/bin/pip'),'install','--disable-pip-version-check','-r',str(root/'services/spatial/requirements.txt')]);write(receipt,dependency_hash)
    sessions=pathlib.Path(config['STUDIO_SPATIAL_ROOT']);sessions.mkdir(parents=True,exist_ok=True);os.chown(sessions,owner.pw_uid,owner.pw_gid);sessions.chmod(0o700)
    write(runtime,json.dumps(config),owner=owner);write(base/'service.env',''.join(name+'='+shlex.quote(str(value))+'\n' for name,value in config.items()))
    write('/etc/systemd/system/'+setup['service']+'.service',setup['unit'],0o644)
    turn_user=pwd.getpwnam('turnserver');os.chown(turn,0,turn_user.pw_gid);turn.chmod(0o640)
    proxy=pathlib.Path('/etc/lightek')/('spatial-'+setup['key']+'.conf');write(proxy,setup['proxy'],0o644)
    found=False
    for vhost in pathlib.Path('/etc/apache2/sites-available').glob('*.conf'):
      text=vhost.read_text();updated=inject_vhosts(text,root,args.domain,proxy)
      if updated!=text:write(vhost,updated,0o644)
      if f'Include "{proxy}"' in updated:found=True
    if not found:raise ValueError('No matching Passenger vhost found for streaming routing')
    run(['a2enmod','proxy','proxy_http','proxy_wstunnel']);run(['apache2ctl','configtest'])
    if pathlib.Path('/etc/ufw/ufw.conf').exists() and 'ENABLED=yes' in pathlib.Path('/etc/ufw/ufw.conf').read_text():
      for port in ['3478/tcp','3478/udp','49160:49200/udp']:run(['ufw','allow',port])
    run(['systemctl','daemon-reload']);run(['systemctl','enable','--now','coturn']);run(['systemctl','restart','coturn']);run(['systemctl','enable',setup['service']]);run(['systemctl','restart',setup['service']]);run(['systemctl','reload','apache2'])
    for attempt in range(20):
      try:
        with urllib.request.urlopen(config['STUDIO_SPATIAL_URL']+'/health',timeout=2) as response:health=json.load(response)
        if not health['ready']:raise ValueError('Streaming runtime dependency is unavailable')
        break
      except Exception:
        if attempt==19:raise
        time.sleep(.5)
    print('LIGHTEK_SPATIAL_RUNTIME_READY='+setup['service'])
if __name__=='__main__':main()
