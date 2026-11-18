#!/usr/bin/env python3
"""Bounded native-backend transfer. Root SSH only; no arbitrary path or command RPC."""
import fcntl, base64, hashlib, json, os, pathlib, re, shutil, subprocess, sys, tarfile

CHUNK = 4 * 1024 * 1024
MAX_ARCHIVE = 4 * 1024 * 1024 * 1024
SECRET_KEYS = {'SECRET_KEY_BASE','LOCKBOX_MASTER_KEY','RAILS_MASTER_KEY','LIGHTEK_VAULT_MASTER_KEY','LIGHTEK_VAULT_KEY_VERSION','ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY','ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY','ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT'}
ACTIONS = {'probe','destination_probe','reserve_target','freeze_export','read_chunk','write_chunk','apply','activate','abort_target','rollback_source','redirect'}

def digest(path):
    h=hashlib.sha256()
    with path.open('rb') as stream:
        for part in iter(lambda:stream.read(1024*1024),b''):h.update(part)
    return h.hexdigest()

def checked_members(archive):
    seen=set(); total=0;members=[]
    for member in archive:
        if len(members)>=100000:raise ValueError('Backend archive contains too many files')
        members.append(member)
        p=pathlib.PurePosixPath(member.name)
        if p.is_absolute() or '..' in p.parts or member.name in seen or not (member.isfile() or member.isdir()):raise ValueError('Unsafe backend archive')
        if p.parts[0] not in {'database.dump','redis.rdb','keys.json','manifest.json','storage','account.json','blobs'}:raise ValueError('Unexpected backend archive member')
        if p.parts[0] not in {'storage','blobs'} and len(p.parts)!=1:raise ValueError('Unexpected backend archive path')
        total+=member.size
        if total>MAX_ARCHIVE:raise ValueError('Backend archive exceeds transfer allowance')
        seen.add(member.name)
    legacy={'database.dump','redis.rdb','keys.json','manifest.json'}.issubset(seen)
    account={'account.json','manifest.json'}.issubset(seen)
    if legacy==account:raise ValueError('Incomplete or mixed backend archive')
    if account and any(p.split('/')[0] in {'storage','database.dump','redis.rdb','keys.json'} for p in seen):raise ValueError('Account archive contains shared runtime material')
    return members

class Transfer:
    def __init__(self,c):
        self.c=c;self.action=c['action']
        if self.action not in ACTIONS:raise ValueError('Unknown backend transfer action')
        if not re.fullmatch(r'[a-f0-9-]{36}',c['operation_key']) or not re.fullmatch(r'[a-f0-9-]{36}',c['member_key']):raise ValueError('Invalid transfer identity')
        if not re.fullmatch(r'[a-z0-9-]+(?:\.[a-z0-9-]+)+',c['domain']):raise ValueError('Invalid backend hostname')
        self.account=bool(c.get('account_snapshot'));self.shared_source=bool(c.get('shared_source'))
        if self.shared_source and not self.account:raise ValueError('Shared hosting requires the account-only protocol')
        runtime=c.get('runtime_domain',c['domain'])
        if not re.fullmatch(r'[a-z0-9-]+(?:\.[a-z0-9-]+)+',runtime):raise ValueError('Invalid runtime hostname')
        if runtime!=c['domain'] and not (self.account and self.shared_source):raise ValueError('Only a shared account may use a different runtime')
        self.base=pathlib.Path('/opt/lightek-sites')/runtime;self.root=self.base/'current'
        profile=c['deployment']
        if profile['app_root']!=str(self.root) or profile['env_file']!=str(self.base/'.env'):raise ValueError('Transfer must target its exact managed runtime')
        if not re.fullmatch(r'[a-zA-Z_][a-zA-Z0-9_-]*',profile['app_user']):raise ValueError('Invalid application user')
        managed=json.loads((self.base/'managed.json').read_text())
        if managed['domain']!=runtime or managed['owner_email']!=c.get('runtime_owner_email',c['owner_email']):raise ValueError('Managed backend ownership mismatch')
        worker='lightek-'+hashlib.sha256(runtime.encode()).hexdigest()[:12]+'-sidekiq'
        if profile['worker_service'].removesuffix('.service')!=worker:raise ValueError('Worker does not belong to this backend')
        self.profile=profile;self.env=self.values();self.state=pathlib.Path('/var/lib/lightek/pwa-transfers')/c['operation_key']
        self.state.mkdir(parents=True,exist_ok=True,mode=0o700);self.state.chmod(0o700)
        self.archive=self.state/'backend.tar';self.flag=self.root/('tmp/pwa-accounts/'+c['member_key']+'.lock' if self.shared_source else 'tmp/pwa-migration.lock')
        binding=self.state/'binding.json';expected={k:c[k] for k in ['domain','member_key','owner_email']}
        if self.account:expected.update(runtime=runtime,account=True,shared_source=self.shared_source)
        if binding.exists() and json.loads(binding.read_text())!=expected:raise ValueError('Transfer operation belongs to another backend')
        binding.write_text(json.dumps(expected));binding.chmod(0o600)
    def values(self):return {k:json.loads(v) for k,v in (line.split('=',1) for line in (self.base/'.env').read_text().splitlines() if '=' in line)}
    def run(self,args,stdin=None,capture=False):
        with (self.state/'private.log').open('ab') as log:
            result=subprocess.run(args,input=stdin,stdout=subprocess.PIPE if capture else log,stderr=log,check=True,timeout=600)
            return result.stdout if capture else None
    def compose(self,*args,stdin=None,capture=False):
        return self.run(['docker','compose','--env-file',str(self.base/'.env'),'-p',self.env['PROJECT'],'-f',str(self.base/'dependencies.yml'),*args],stdin,capture)
    def database_file(self,path,restore=False):
        command = 'pg_restore --clean --if-exists --no-owner --no-acl --exit-on-error' if restore else 'pg_dump --format=custom --no-owner --no-acl'
        args=['docker','compose','--env-file',str(self.base/'.env'),'-p',self.env['PROJECT'],'-f',str(self.base/'dependencies.yml'),'exec','-T','-e','PGOPTIONS=-c default_transaction_read_only=off','db','sh','-c',command+' -U "$POSTGRES_USER" -d "$POSTGRES_DB"']
        with path.open('rb' if restore else 'wb') as stream,(self.state/'private.log').open('ab') as log:
            subprocess.run(args,stdin=stream if restore else subprocess.DEVNULL,stdout=log if restore else stream,stderr=log,check=True,timeout=600)
    def db(self,sql):
        return self.compose('exec','-T','-e','PGOPTIONS=-c default_transaction_read_only=off','db','sh','-c','psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "$1"','transfer',sql,capture=True)
    def rails(self,action,**extra):
        source='''require "json"; c=JSON.parse(STDIN.read); result = case c["action"]
when "account_freeze" then LightekPwa::AccountSnapshot.new(c).freeze!
when "account_thaw" then LightekPwa::AccountSnapshot.new(c).thaw!
when "account_commit" then LightekPwa::AccountSnapshot.new(c).commit!(c.fetch("destination_hostname"))
when "account_export" then LightekPwa::SourceRuntime.control { LightekPwa::AccountSnapshot.new(c).export!(c.fetch("directory")) }
when "account_import" then LightekPwa::AccountSnapshot.import!(c,c.fetch("directory"))
when "rewrite" then LightekPwa::NativeBackend.rewrite!(c)
when "activate" then LightekPwa::NativeBackend.activate!(c)
else LightekPwa::NativeBackend.call(c)
end; puts "PWA_BACKEND="+JSON.generate(result)'''
        output=self.run(['sudo','-u',self.profile['app_user'],'-H','env','PGOPTIONS=-c default_transaction_read_only=off','python3',str(self.base/'run-app.py'),'bundle','exec','rails','runner',source],json.dumps({**self.c,'action':action,**extra}).encode(),True)
        line=next(x for x in output.decode().splitlines() if x.startswith('PWA_BACKEND='));return json.loads(line[12:])
    def worker(self,action):self.run(['systemctl',action,self.profile['worker_service']])
    def readonly(self,value):
        db=self.env['POSTGRES_DB'];name='"'+db.replace('"','""')+'"'
        self.db('ALTER DATABASE '+name+' SET default_transaction_read_only = '+('on' if value else 'off'))
        self.db("SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = current_database() AND pid <> pg_backend_pid()")
    def freeze(self):
        if self.shared_source:
            proof=self.rails('account_freeze')
            if proof['status']!='frozen':raise ValueError('Account did not accept the write hold')
            return proof
        if self.flag.exists() and self.flag.read_text()!=self.c['operation_key']:raise ValueError('Another transfer owns the write freeze')
        self.flag.write_text(self.c['operation_key']);self.worker('stop');self.readonly(True)
    def thaw(self):
        if self.shared_source:
            if self.rails('account_thaw')['status']!='active':raise ValueError('Account write hold could not be released')
            return
        if not self.flag.exists() or self.flag.read_text()!=self.c['operation_key']:raise ValueError('Write-freeze ownership mismatch')
        self.readonly(False);self.flag.unlink();self.worker('start')
        self.run(['passenger-config','restart-app',str(self.root),'--ignore-app-not-running'])
    def storage(self):
        expected=self.base/'shared/storage'
        actual=(self.root/'storage').resolve()
        if actual!=expected or expected.is_symlink() or expected.parent.is_symlink():raise ValueError('Storage is outside its exact managed backend')
        return actual
    def vhost_path(self):
        prefix = 'lightek-app-'+self.c['member_key'] if self.shared_source and self.c['domain']!=self.c['runtime_domain'] else 'lightek-'+self.c['domain']
        return pathlib.Path('/etc/apache2/sites-available')/(prefix+'-ssl.conf')
    def storage_digest(self,root):
        h=hashlib.sha256()
        for p in sorted(root.rglob('*')):
            if p.is_symlink():raise ValueError('Storage symlinks cannot be migrated')
            if p.is_file():h.update((str(p.relative_to(root))+'\0'+str(p.stat().st_size)+'\0'+digest(p)+'\n').encode())
        return h.hexdigest()
    def export(self):
        if self.archive.exists() and (self.state/'export.json').exists():return json.loads((self.state/'export.json').read_text())
        if self.shared_source:return self.export_account()
        proof=self.rails('probe');self.freeze();proof=self.rails('probe')
        if shutil.disk_usage(self.base).free<1024*1024*1024:raise ValueError('Not enough space for a retained migration snapshot')
        # Snapshot uses this application's own dependency project and storage only.
        self.database_file(self.state/'database.dump')
        self.compose('exec','-T','redis','redis-cli','SAVE')
        self.compose('cp','redis:/data/dump.rdb',str(self.state/'redis.rdb'))
        (self.state/'keys.json').write_text(json.dumps({k:v for k,v in self.env.items() if k in SECRET_KEYS}))
        storage=self.storage();proof['storage_sha256']=self.storage_digest(storage)
        proof['source_hostname']=self.c['domain'];proof['source_sha']=self.run(['git','-C',str(self.root),'rev-parse','HEAD'],capture=True).decode().strip()
        (self.state/'manifest.json').write_text(json.dumps(proof))
        with tarfile.open(str(self.archive)+'.partial','w') as archive:
            for name in ['database.dump','redis.rdb','keys.json','manifest.json']:archive.add(self.state/name,arcname=name)
            archive.add(storage,arcname='storage',recursive=True)
        pathlib.Path(str(self.archive)+'.partial').replace(self.archive);self.archive.chmod(0o600)
        if self.archive.stat().st_size>MAX_ARCHIVE:raise ValueError('Backend snapshot exceeds transfer allowance')
        receipt={**proof,'bytes':self.archive.stat().st_size,'sha256':digest(self.archive),'status':'frozen'}
        (self.state/'export.json').write_text(json.dumps(receipt));return receipt
    def reserve_target(self):
        if (self.state/'activation-intent').exists():raise ValueError('Destination activation already began')
        if (self.state/'apply-started').exists():
            if not self.flag.exists() or self.flag.read_text()!=self.c['operation_key']:raise ValueError('Destination write hold changed')
            return {'status':'reserved'}
        proof=self.rails('destination_probe');self.freeze()
        # Reject customer work committed between preflight and the write hold.
        proof=self.rails('destination_probe')
        (self.state/'destination-proof.json').write_text(json.dumps(proof))
        self.database_file(self.state/'destination-before.dump')
        self.compose('exec','-T','redis','redis-cli','SAVE')
        self.compose('cp','redis:/data/dump.rdb',str(self.state/'destination-before.rdb'))
        (self.state/'environment-before').write_text((self.base/'.env').read_text())
        (self.state/'apply-started').write_text('1')
        return {'status':'reserved'}
    def apply(self):
        if (self.state/'activation-intent').exists():raise ValueError('Destination activation has begun; never overwrite newer writes')
        if self.archive.stat().st_size!=int(self.c['bytes']) or digest(self.archive)!=self.c['sha256']:raise ValueError('Transferred archive checksum mismatch')
        if (self.state/'applied.json').exists():return {**json.loads((self.state/'applied.json').read_text()),'status':'verified','sha256':self.c['sha256']}
        target=self.state/'unpack'
        if target.exists():shutil.rmtree(target)
        target.mkdir(mode=0o700)
        with tarfile.open(self.archive) as archive:
            for member in checked_members(archive):
                p=target/member.name
                if member.isdir():p.mkdir(parents=True,exist_ok=True)
                else:
                    p.parent.mkdir(parents=True,exist_ok=True)
                    with archive.extractfile(member) as source,p.open('xb') as out:shutil.copyfileobj(source,out)
        manifest=json.loads((target/'manifest.json').read_text())
        if manifest['member_key']!=self.c['member_key'] or manifest['source_sha']!=self.run(['git','-C',str(self.root),'rev-parse','HEAD'],capture=True).decode().strip():raise ValueError('Backend source revision or identity differs')
        if not (self.state/'apply-started').exists():self.reserve_target()
        destination=json.loads((self.state/'destination-proof.json').read_text())
        if destination['schema']!=manifest['schema']:raise ValueError('Source and destination schemas differ')
        if not self.flag.exists() or self.flag.read_text()!=self.c['operation_key']:raise ValueError('Destination write hold changed')
        if self.account:return self.apply_account(target,manifest)
        if (target/'account.json').exists():raise ValueError('Account archive cannot use the whole-runtime importer')
        keys=json.loads((target/'keys.json').read_text())
        if set(keys)-SECRET_KEYS:raise ValueError('Unexpected protected configuration')
        values=self.values();values.update(keys)
        (self.base/'.env').write_text(''.join(k+'='+json.dumps(str(v))+'\n' for k,v in values.items()));(self.base/'.env').chmod(0o600)
        self.database_file(target/'database.dump',restore=True)
        storage=self.storage();backup=self.state/'destination-storage-before'
        if not backup.exists():shutil.copytree(storage,backup)
        for child in storage.iterdir():shutil.rmtree(child) if child.is_dir() else child.unlink()
        shutil.copytree(target/'storage',storage,dirs_exist_ok=True)
        self.run(['chown','-R',self.profile['app_user']+':'+self.profile['app_user'],str(storage)])
        self.compose('stop','redis');self.compose('run','--rm','--entrypoint','sh','redis','-c','rm -rf /data/appendonlydir /data/dump.rdb')
        self.compose('cp',str(target/'redis.rdb'),'redis:/data/dump.rdb');self.compose('start','redis')
        result=self.rails('rewrite',source_hostname=manifest['source_hostname'])
        # Sessions are deliberately revoked; all other database table counts must match.
        if result['counts']!=manifest['counts'] or self.storage_digest(storage)!=manifest['storage_sha256']:raise ValueError('Imported backend verification failed')
        (self.state/'applied.json').write_text(json.dumps(result));return {**result,'status':'verified','sha256':self.c['sha256']}
    def account_directory(self,name):
        import pwd
        directory=self.base/'shared/tmp/pwa-transfers'/self.c['operation_key']/name
        directory.mkdir(parents=True,exist_ok=True,mode=0o700)
        if any(path.is_symlink() for path in [directory.parent.parent,directory.parent,directory]):raise ValueError('Account snapshot paths cannot be symlinks')
        user=pwd.getpwnam(self.profile['app_user'])
        for path in [directory.parent.parent,directory.parent,directory]:
            os.chown(path,user.pw_uid,user.pw_gid);path.chmod(0o700)
        return directory
    def export_account(self):
        proof=self.freeze()
        if shutil.disk_usage(self.base).free < int(proof['media_bytes'])*2 + 640*1024*1024:
            self.thaw();raise ValueError('Not enough space for a retained account snapshot')
        directory=self.account_directory('export')
        proof=self.rails('account_export',directory=str(directory))
        proof['source_hostname']=self.c['domain'];proof['source_sha']=self.run(['git','-C',str(self.root),'rev-parse','HEAD'],capture=True).decode().strip()
        (directory/'manifest.json').write_text(json.dumps(proof))
        with tarfile.open(str(self.archive)+'.partial','w') as archive:
            for name in ['account.json','manifest.json','blobs']:archive.add(directory/name,arcname=name,recursive=True)
        pathlib.Path(str(self.archive)+'.partial').replace(self.archive);self.archive.chmod(0o600)
        if self.archive.stat().st_size>MAX_ARCHIVE:raise ValueError('Account snapshot exceeds transfer allowance')
        receipt={**proof,'bytes':self.archive.stat().st_size,'sha256':digest(self.archive),'status':'frozen'}
        (self.state/'export.json').write_text(json.dumps(receipt));return receipt
    def apply_account(self,target,manifest):
        if manifest.get('format')!='account-v1' or not (target/'account.json').is_file():raise ValueError('Expected an account-only snapshot')
        directory=self.account_directory('import')
        shutil.copytree(target,directory,dirs_exist_ok=True)
        self.run(['chown','-R',self.profile['app_user']+':'+self.profile['app_user'],str(directory)])
        storage=self.storage();backup=self.state/'destination-storage-before'
        if not backup.exists():shutil.copytree(storage,backup)
        proof=self.rails('account_import',directory=str(directory))
        if proof['counts']!=manifest['counts'] or proof['member_key']!=self.c['member_key']:raise ValueError('Account import verification failed')
        self.rails('rewrite',source_hostname=manifest['source_hostname'])
        # The destination's own secrets remain in place. Shared jobs, sessions
        # and Redis contents are never imported from the free hosting service.
        self.compose('exec','-T','redis','redis-cli','FLUSHDB')
        result={**proof,'status':'verified','sha256':self.c['sha256']}
        (self.state/'applied.json').write_text(json.dumps(result));return result
    def call(self):
        a=self.action
        if a in {'probe','destination_probe'}:return self.rails(a)
        if a=='reserve_target':return self.reserve_target()
        if a=='freeze_export':return self.export()
        if a=='read_chunk':
            offset=int(self.c['offset'])
            if offset<0 or offset>self.archive.stat().st_size:raise ValueError('Invalid transfer offset')
            with self.archive.open('rb') as f:f.seek(offset);data=f.read(CHUNK)
            return {'offset':offset,'data':base64.b64encode(data).decode(),'sha256':hashlib.sha256(data).hexdigest()}
        if a=='write_chunk':
            data=base64.b64decode(self.c['data'],validate=True);offset=int(self.c['offset'])
            if len(data)>CHUNK or offset<0 or offset+len(data)>MAX_ARCHIVE or hashlib.sha256(data).hexdigest()!=self.c['chunk_sha256']:raise ValueError('Invalid backend chunk')
            size=self.archive.stat().st_size if self.archive.exists() else 0
            if offset<size:
                with self.archive.open('rb') as f:f.seek(offset);old=f.read(len(data))
                if old!=data:raise ValueError('Retry chunk differs from retained bytes')
                return {'copied_bytes':offset+len(data)}
            if offset!=size:raise ValueError('Out-of-order backend chunk')
            with self.archive.open('ab') as f:f.write(data);f.flush();os.fsync(f.fileno())
            return {'copied_bytes':offset+len(data)}
        if a=='apply':return self.apply()
        if a=='activate':
            if not (self.state/'applied.json').exists():raise ValueError('No verified backend import')
            self.rails('activate')
            (self.state/'activation-intent').write_text('1')
            # Protected env values must also reach Passenger after import.
            def quote(v):return '"'+str(v).replace('\\','\\\\').replace('"','\\"')+'"'
            values=self.values();values['LIGHTEK_PWA_MEMBER_BACKEND']='false';values['LIGHTEK_PWA_SHARED_HOSTING']='false';(self.base/'.env').write_text(''.join(k+'='+json.dumps(str(v))+'\n' for k,v in values.items()));(self.base/'passenger-env.conf').write_text(''.join('SetEnv '+k+' '+quote(v)+'\n' for k,v in values.items()))
            self.run(['apache2ctl','configtest']);self.run(['systemctl','reload','apache2'])
            if self.flag.exists():self.thaw()
            else:self.readonly(False);self.worker('start');self.run(['passenger-config','restart-app',str(self.root),'--ignore-app-not-running'])
            return {'status':'active'}
        if a=='abort_target':
            if (self.state/'activation-intent').exists():raise ValueError('Destination may contain new writes; reverse transfer required')
            if (self.state/'aborted').exists():return {'status':'aborted'}
            if (self.state/'destination-restored').exists():
                if self.flag.exists():self.thaw()
                else:self.readonly(False);self.worker('start')
                (self.state/'aborted').write_text('1');return {'status':'aborted'}
            if (self.state/'apply-started').exists():
                self.freeze();self.database_file(self.state/'destination-before.dump',restore=True)
                (self.base/'.env').write_text((self.state/'environment-before').read_text())
                backup=self.state/'destination-storage-before'
                if backup.exists():
                    storage=self.storage()
                    for child in storage.iterdir():shutil.rmtree(child) if child.is_dir() else child.unlink()
                    shutil.copytree(backup,storage,dirs_exist_ok=True);self.run(['chown','-R',self.profile['app_user']+':'+self.profile['app_user'],str(storage)])
                self.compose('stop','redis');self.compose('run','--rm','--entrypoint','sh','redis','-c','rm -rf /data/appendonlydir /data/dump.rdb');self.compose('cp',str(self.state/'destination-before.rdb'),'redis:/data/dump.rdb');self.compose('start','redis')
                (self.state/'destination-restored').write_text('1');self.thaw()
            if self.flag.exists():self.thaw()
            (self.state/'aborted').write_text('1');return {'status':'aborted'}
        if a=='rollback_source':
            if (self.state/'source-committed').exists():raise ValueError('Destination is active; reverse transfer is required')
            backup=self.state/'vhost-before'
            if backup.exists():
                path=self.vhost_path();path.write_text(backup.read_text());self.run(['apache2ctl','configtest']);self.run(['systemctl','reload','apache2'])
            if not (self.state/'source-restored').exists():
                if self.shared_source:
                    if self.flag.exists():self.thaw()
                    (self.state/'source-restored').write_text('1');return {'status':'active'}
                if self.flag.exists():self.thaw()
                else:self.readonly(False);self.worker('start');self.run(['passenger-config','restart-app',str(self.root),'--ignore-app-not-running'])
                (self.state/'source-restored').write_text('1')
            return {'status':'active'}
        if a=='redirect':
            host=self.c['destination_hostname']
            if not re.fullmatch(r'[a-z0-9-]+(?:\.[a-z0-9-]+)+',host):raise ValueError('Invalid redirect hostname')
            if self.shared_source:
                proof=json.loads((self.state/'export.json').read_text())
                if not self.archive.exists() or digest(self.archive)!=proof['sha256']:raise ValueError('Retained account snapshot is missing or changed')
            path=self.vhost_path();text=path.read_text()
            if not (self.state/'vhost-before').exists():(self.state/'vhost-before').write_text(text)
            if self.shared_source:
                marker='# LIGHTEK ACCOUNT CUTOVER BEGIN'
                block=marker+'\nRewriteEngine On\nRewriteCond %{REQUEST_URI} !^/(?:__lightek/|up/?$|\\.well-known/)\nRewriteRule ^ https://'+host+'%{REQUEST_URI} [R=307,L]\n# LIGHTEK ACCOUNT CUTOVER END\n'
                if marker in text:text=re.sub(r'# LIGHTEK ACCOUNT CUTOVER BEGIN.*?# LIGHTEK ACCOUNT CUTOVER END\n?',lambda _:block,text,flags=re.S)
                else:text=text.replace('</VirtualHost>',block+'</VirtualHost>')
            else:text=re.sub(r'(?m)^\s*PassengerAppRoot.*$', 'Redirect 307 / https://'+host+'/',text)
            path.write_text(text);self.run(['apache2ctl','configtest']);self.run(['systemctl','reload','apache2'])
            if self.shared_source:
                receipt=self.rails('account_commit',destination_hostname=host)
                (self.state/'source-committed').write_text(host);return receipt
            return {'status':'redirecting'}

def main():
    try:
        instance=Transfer(json.load(sys.stdin))
        runtime_state=pathlib.Path('/var/lib/lightek/fleet')/hashlib.sha256(str(instance.root.resolve()).encode()).hexdigest()[:24]
        runtime_state.mkdir(parents=True,exist_ok=True,mode=0o700)
        with pathlib.Path('/var/lock/lightek-site-'+instance.c['domain']+'.lock').open('a') as lock,(runtime_state/'update.lock').open('a') as runtime_lock:
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            fcntl.flock(runtime_lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            print(json.dumps(instance.call()))
    except Exception as error:
        print(json.dumps({'status':'failed','error_class':type(error).__name__}));return 1
    return 0
if __name__=='__main__':sys.exit(main())
