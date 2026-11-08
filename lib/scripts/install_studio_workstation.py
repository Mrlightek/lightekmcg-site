#!/usr/bin/env python3
"""Idempotent root deployment step for the loopback native desktop gateway."""
import argparse
import json
import hashlib
import os
from pathlib import Path
import re
import subprocess
import tempfile


def configuration(app_root, app_user, app_name, state_root, port=None):
    identity=hashlib.sha256(str(app_root).encode()).hexdigest()[:12]
    port=port or 19080+int(identity,16)%10000
    if not re.fullmatch(r'[a-zA-Z0-9_-]+', app_name) or not re.fullmatch(r'[a-z_][a-z0-9_-]*', app_user): raise ValueError('Invalid service account or application name')
    if not 1024 <= port <= 65535: raise ValueError('Invalid loopback port')
    # ExecStart and path-list values use quotes; WorkingDirectory takes a raw
    # absolute path. Reject systemd specifiers, control characters and
    # quotes rather than trying to interpret deployment inputs as unit syntax.
    for path in (str(app_root), str(state_root)):
        if not path.startswith('/') or any(c in path for c in '\n\r\x00%"\\'): raise ValueError('Unsupported service path')
    unit=f'''[Unit]
Description=Lightek native Studio workstation gateway
After=network.target docker.service
Requires=docker.service
[Service]
Type=simple
User={app_user}
WorkingDirectory={app_root}
ExecStart=/usr/bin/python3 "{app_root}/lib/scripts/studio_workstation_gateway.py" --root "{state_root}" --port {port}
Environment=PYTHONDONTWRITEBYTECODE=1
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths="{state_root}"
[Install]
WantedBy=multi-user.target
'''
    apache=f'''# Native desktop access is checked by the workstation gateway.
# Upgrade tunneling uses mod_proxy_http (Apache 2.4.47+).
<Location "/studio-workstations/">
    <IfModule passenger_module>
        PassengerEnabled off
    </IfModule>
    ProxyPreserveHost On
    ProxyPass "http://127.0.0.1:{port}/studio-workstations/" upgrade=websocket timeout=14400
    ProxyPassReverse "http://127.0.0.1:{port}/studio-workstations/"
    RequestHeader set X-Forwarded-Proto expr=%{{REQUEST_SCHEME}}
</Location>
'''
    service='lightek-studio-'+identity
    cleanup_unit=f'''[Unit]
Description=Lightek expired workstation cleanup
[Service]
Type=oneshot
User={app_user}
ExecStart=/usr/bin/python3 "{app_root}/lib/scripts/studio_workstation_cleanup.py" --root "{state_root}"
NoNewPrivileges=true
'''
    cleanup_timer=f'''[Unit]
Description=Expire Lightek native workstations
[Timer]
OnBootSec=2min
OnUnitActiveSec=1min
Unit={service}-cleanup.service
[Install]
WantedBy=timers.target
'''
    return {'unit':unit,'apache':apache,'service':service,'conf':service,'port':port,'cleanup_unit':cleanup_unit,'cleanup_timer':cleanup_timer}


def validate_units(config, run=None):
    """Parse staged units before changing services, vhosts or gateway settings."""
    run = run or subprocess.run
    files = {
        config['service']+'.service':config['unit'],
        config['service']+'-cleanup.service':config['cleanup_unit'],
        config['service']+'-cleanup.timer':config['cleanup_timer'],
    }
    with tempfile.TemporaryDirectory(prefix='lightek-studio-units-') as folder:
        paths=[]
        for name, content in files.items():
            path=Path(folder)/name;path.write_text(content);paths.append(str(path))
        try:
            run(['systemd-analyze','verify',*paths],check=True,text=True,capture_output=True)
        except subprocess.CalledProcessError as error:
            raise RuntimeError('Studio service configuration is invalid: '+(error.stderr or str(error)).strip()) from error


def patch_vhosts(text, app_root, domain, include_path):
    count=0
    marker='IncludeOptional "'+str(include_path)+'"'
    def update(match):
        nonlocal count
        block=match.group(0)
        names=[];roots=[]
        for line in block.splitlines():
            line=line.split('#',1)[0]
            found=re.match(r'^\s*Server(?:Name|Alias)\s+(.+)',line,re.I)
            if found:names.extend(name.lower().split(':')[0] for name in found.group(1).split())
            found=re.match(r'^\s*(?:DocumentRoot|PassengerAppRoot)\s+(.+)',line,re.I)
            if found:roots.append(found.group(1).strip().strip('"').rstrip('/'))
        if domain.lower() not in names and str(app_root).rstrip('/') not in roots and str(app_root/'public').rstrip('/') not in roots:return block
        count+=1
        if marker in block:return block
        if re.search(r'^\s*(?:ProxyPass|<Location).*?/studio-workstations/',block,re.I|re.M):raise ValueError('A workstation proxy is already configured in this virtual host')
        return re.sub(r'</VirtualHost\s*>','    '+marker+'\n</VirtualHost>',block,count=1,flags=re.I)
    return re.sub(r'<VirtualHost\s+([^>]+)>.*?</VirtualHost\s*>',update,text,flags=re.I|re.S),count

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--app-root',type=Path,required=True);parser.add_argument('--app-user',required=True);parser.add_argument('--app-name',required=True);parser.add_argument('--state-root',type=Path);parser.add_argument('--port',type=int);parser.add_argument('--domain',required=True);parser.add_argument('--dry-run',action='store_true');args=parser.parse_args()
    state=args.state_root or args.app_root/'storage/studio-workstations'
    config=configuration(args.app_root,args.app_user,args.app_name,state,args.port)
    if args.dry_run:
        print(json.dumps(config));return
    if os.geteuid()!=0: raise SystemExit('Run the service installer from the root deployment pipeline')
    validate_units(config)
    def run(command): subprocess.run(command,check=True)
    unit=Path('/etc/systemd/system')/(config['service']+'.service')
    conf=Path('/etc/apache2/conf-available')/(config['conf']+'.conf')
    changed={};matches=0
    for link in Path('/etc/apache2/sites-enabled').glob('*.conf'):
        path=link.resolve()
        if path in changed:continue
        content=path.read_text();updated,count=patch_vhosts(content,args.app_root,args.domain,conf)
        matches+=count
        if updated!=content:changed[path]=updated
    if not matches:raise SystemExit('No application virtual host matches the workstation deployment')
    port_config=state/'gateway.json'
    cleanup_unit=unit.with_name(config['service']+'-cleanup.service')
    cleanup_timer=unit.with_name(config['service']+'-cleanup.timer')
    snapshots={path:path.read_bytes() if path.exists() else None for path in [unit,conf,port_config,cleanup_unit,cleanup_timer,*changed]}
    timer_active=subprocess.run(['systemctl','is-active','--quiet',cleanup_timer.name]).returncode==0
    previously_active=subprocess.run(['systemctl','is-active','--quiet',config['service']]).returncode==0
    try:
        unit.write_text(config['unit']);conf.write_text(config['apache'])
        cleanup_unit.write_text(config['cleanup_unit']);cleanup_timer.write_text(config['cleanup_timer'])
        port_config.write_text(json.dumps({'port':config['port']}))
        for path,content in changed.items():path.write_text(content)
        run(['a2enmod','proxy','proxy_http','headers'])
        run(['apache2ctl','configtest']);run(['systemctl','daemon-reload']);run(['systemctl','enable','--now',config['service']]);run(['systemctl','restart',config['service']]);run(['systemctl','is-active','--quiet',config['service']])
        run(['systemctl','enable','--now',cleanup_timer.name]);run(['systemctl','reload','apache2'])
    except Exception:
        if not timer_active:subprocess.run(['systemctl','disable','--now',cleanup_timer.name])
        if not previously_active:subprocess.run(['systemctl','stop',config['service']])
        for path,content in snapshots.items():
            if content is None:path.unlink(missing_ok=True)
            else:path.write_bytes(content)
        subprocess.run(['systemctl','daemon-reload'])
        if previously_active:subprocess.run(['systemctl','restart',config['service']])
        if subprocess.run(['apache2ctl','configtest']).returncode==0:subprocess.run(['systemctl','reload','apache2'])
        raise



if __name__=='__main__':main()
