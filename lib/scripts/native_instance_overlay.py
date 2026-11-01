#!/usr/bin/env python3
"""Maintain the installer's two known boot overlays without hiding customer edits."""
import argparse,hashlib,json,pathlib,subprocess
PATHS=['config/application.rb','config/routes.rb']
def restore(root):
    marker=root/'tmp/native-instance-overlay.json'
    if not marker.exists():return
    data=json.loads(marker.read_text())
    for name in PATHS:
        if hashlib.sha256((root/name).read_bytes()).hexdigest()!=data[name]:raise ValueError('Installer overlay was edited; reconcile '+name+' before updating')
    subprocess.run(['git','update-index','--no-skip-worktree','--',*PATHS],cwd=root,check=True)
    subprocess.run(['git','checkout','--',*PATHS],cwd=root,check=True)
    marker.unlink()
def apply(root):
    # Each instance has its own secrets; repository-encrypted credentials are not its keys.
    encrypted=[path for path in [root/'config/credentials.yml.enc',*(root/'config/credentials').glob('*.yml.enc')] if path.is_file()]
    for path in encrypted:
        subprocess.run(['git','update-index','--skip-worktree','--',str(path.relative_to(root))],cwd=root,check=True)
        path.unlink()
    # Import definitions only; the packager main is not executed.
    source=(root/'script/lightek/website_deploy.sh').read_text().split("<<'LIGHTEK_PYTHON'\n",1)[1].split('\nLIGHTEK_PYTHON',1)[0]
    scope={'__name__':'native_overlay'};exec(compile(source,'website_deploy.sh','exec'),scope)
    for name,function in zip(PATHS,['add_boot_sync_hook','add_routes']):
        path=root/name;path.write_text(scope[function](path.read_text()))
    data={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in PATHS}
    (root/'tmp').mkdir(exist_ok=True);marker=root/'tmp/native-instance-overlay.json';marker.write_text(json.dumps(data));marker.chmod(0o600)
    subprocess.run(['git','update-index','--skip-worktree','--',*PATHS],cwd=root,check=True)
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['apply','restore']);parser.add_argument('root');args=parser.parse_args();globals()[args.action](pathlib.Path(args.root))
