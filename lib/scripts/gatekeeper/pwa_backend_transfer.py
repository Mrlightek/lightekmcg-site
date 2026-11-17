#!/usr/bin/env python3
"""Bounded native-backend transfer. Root SSH only; no arbitrary path or command RPC."""
import fcntl, base64, hashlib, json, os, pathlib, re, shutil, subprocess, sys, tarfile

CHUNK = 4 * 1024 * 1024
MAX_ARCHIVE = 4 * 1024 * 1024 * 1024
SECRET_KEYS = {'SECRET_KEY_BASE','LOCKBOX_MASTER_KEY','RAILS_MASTER_KEY','LIGHTEK_VAULT_MASTER_KEY','LIGHTEK_VAULT_KEY_VERSION','ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY','ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY','ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT'}
ACTIONS = {'probe','destination_probe','freeze_export','read_chunk','write_chunk','apply','activate','abort_target','rollback_source','redirect'}

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
        if p.parts[0] not in {'database.dump','redis.rdb','keys.json','manifest.json','storage'}:raise ValueError('Unexpected backend archive member')
        if p.parts[0]!='storage' and len(p.parts)!=1:raise ValueError('Unexpected backend archive path')
        total+=member.size
        if total>MAX_ARCHIVE:raise ValueError('Backend archive exceeds transfer allowance')
        seen.add(member.name)
    if not {'database.dump','redis.rdb','keys.json','manifest.json'}.issubset(seen):raise ValueError('Incomplete backend archive')
    return members

class Transfer:
    def __init__(self,c):
        self.c=c;self.action=c['action']
        if self.action not in ACTIONS:raise ValueError('Unknown backend transfer action')
        if not re.fullmatch(r'[a-f0-9-]{36}',c['operation_key']) or not re.fullmatch(r'[a-f0-9-]{36}',c['member_key']):raise ValueError('Invalid transfer identity')
        if not re.fullmatch(r'[a-z0-9-]+(?:\.[a-z0-9-]+)+',c['domain']):raise ValueError('Invalid backend hostname')
        self.base=pathlib.Path('/opt/lightek-sites')/c['domain'];self.root=self.base/'current'
        profile=c['deployment']
        if profile['app_root']!=str(self.root) or profile['env_file']!=str(self.base/'.env'):raise ValueError('Transfer must target its exact managed runtime')
        if not re.fullmatch(r'[a-zA-Z_][a-zA-Z0-9_-]*',profile['app_user']):raise ValueError('Invalid application user')
        managed=json.loads((self.base/'managed.json').read_text())
        if managed['domain']!=c['domain'] or managed['owner_email']!=c['owner_email']:raise ValueError('Managed backend ownership mismatch')
        worker='lightek-'+hashlib.sha256(c['domain'].encode()).hexdigest()[:12]+'-sidekiq'
        if profile['worker_service'].removesuffix('.service')!=worker:raise ValueError('Worker does not belong to this backend')
        self.profile=profile;self.env=self.values();self.state=pathlib.Path('/var/lib/lightek/pwa-transfers')/c['operation_key']
        self.state.mkdir(parents=True,exist_ok=True,mode=0o700);self.state.chmod(0o700)
        self.archive=self.state/'backend.tar';self.flag=self.root/'tmp/pwa-migration.lock'
        binding=self.state/'binding.json';expected={k:c[k] for k in ['domain','member_key','owner_email']}
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
        source='require "json"; c=JSON.parse(STDIN.read); puts "PWA_BACKEND="+JSON.generate(c["action"]=="rewrite" ? LightekPwa::NativeBackend.rewrite!(c) : LightekPwa::NativeBackend.call(c))'
        output=self.run(['sudo','-u',self.profile['app_user'],'-H','env','PGOPTIONS=-c default_transaction_read_only=off','python3',str(self.base/'run-app.py'),'bundle','exec','rails','runner',source],json.dumps({**self.c,'action':action,**extra}).encode(),True)
        line=next(x for x in output.decode().splitlines() if x.startswith('PWA_BACKEND='));return json.loads(line[12:])
    def worker(self,action):self.run(['systemctl',action,self.profile['worker_service']])
    def readonly(self,value):
        db=self.env['POSTGRES_DB'];name='"'+db.replace('"','""')+'"'
        self.db('ALTER DATABASE '+name+' SET default_transaction_read_only = '+('on' if value else 'off'))
        self.db("SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = current_database() AND pid <> pg_backend_pid()")
    def freeze(self):
        if self.flag.exists() and self.flag.read_text()!=self.c['operation_key']:raise ValueError('Another transfer owns the write freeze')
        self.flag.write_text(self.c['operation_key']);self.worker('stop');self.readonly(True)
    def thaw(self):
        if not self.flag.exists() or self.flag.read_text()!=self.c['operation_key']:raise ValueError('Write-freeze ownership mismatch')
        self.readonly(False);self.flag.unlink();self.worker('start')
        self.run(['passenger-config','restart-app',str(self.root),'--ignore-app-not-running'])
    def storage(self):
        expected=self.base/'shared/storage'
        actual=(self.root/'storage').resolve()
        if actual!=expected or expected.is_symlink() or expected.parent.is_symlink():raise ValueError('Storage is outside its exact managed backend')
        return actual
    def storage_digest(self,root):
        h=hashlib.sha256()
        for p in sorted(root.rglob('*')):
            if p.is_symlink():raise ValueError('Storage symlinks cannot be migrated')
            if p.is_file():h.update((str(p.relative_to(root))+'\0'+str(p.stat().st_size)+'\0'+digest(p)+'\n').encode())
        return h.hexdigest()
    def export(self):
        if self.archive.exists() and (self.state/'export.json').exists():return json.loads((self.state/'export.json').read_text())
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
        if not (self.state/'apply-started').exists():
            destination=self.rails('destination_probe')
            if destination['schema']!=manifest['schema']:raise ValueError('Source and destination schemas differ')
            self.freeze();self.database_file(self.state/'destination-before.dump');self.compose('exec','-T','redis','redis-cli','SAVE');self.compose('cp','redis:/data/dump.rdb',str(self.state/'destination-before.rdb'));(self.state/'environment-before').write_text((self.base/'.env').read_text());(self.state/'apply-started').write_text('1')
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
    def call(self):
        a=self.action
        if a in {'probe','destination_probe'}:return self.rails(a)
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
            (self.state/'activation-intent').write_text('1')
            # Protected env values must also reach Passenger after import.
            def quote(v):return '"'+str(v).replace('\\','\\\\').replace('"','\\"')+'"'
            values=self.values();values['LIGHTEK_PWA_MEMBER_BACKEND']='false';(self.base/'.env').write_text(''.join(k+'='+json.dumps(str(v))+'\n' for k,v in values.items()));(self.base/'passenger-env.conf').write_text(''.join('SetEnv '+k+' '+quote(v)+'\n' for k,v in values.items()))
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
            (self.state/'aborted').write_text('1');return {'status':'aborted'}
        if a=='rollback_source':
            backup=self.state/'vhost-before'
            if backup.exists():
                path=pathlib.Path('/etc/apache2/sites-available')/('lightek-'+self.c['domain']+'-ssl.conf');path.write_text(backup.read_text());self.run(['apache2ctl','configtest']);self.run(['systemctl','reload','apache2'])
            if not (self.state/'source-restored').exists():
                if self.flag.exists():self.thaw()
                else:self.readonly(False);self.worker('start');self.run(['passenger-config','restart-app',str(self.root),'--ignore-app-not-running'])
                (self.state/'source-restored').write_text('1')
            return {'status':'active'}
        if a=='redirect':
            host=self.c['destination_hostname']
            if not re.fullmatch(r'[a-z0-9-]+(?:\.[a-z0-9-]+)+',host):raise ValueError('Invalid redirect hostname')
            path=pathlib.Path('/etc/apache2/sites-available')/('lightek-'+self.c['domain']+'-ssl.conf');text=path.read_text()
            if not (self.state/'vhost-before').exists():(self.state/'vhost-before').write_text(text)
            text=re.sub(r'(?m)^PassengerAppRoot.*$', 'Redirect 307 / https://'+host+'/',text)
            path.write_text(text);self.run(['apache2ctl','configtest']);self.run(['systemctl','reload','apache2']);return {'status':'redirecting'}

def main():
    try:
        instance=Transfer(json.load(sys.stdin))
        with pathlib.Path('/var/lock/lightek-site-'+instance.c['domain']+'.lock').open('a') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            print(json.dumps(instance.call()))
    except Exception as error:
        print(json.dumps({'status':'failed','error_class':type(error).__name__}));return 1
    return 0
if __name__=='__main__':sys.exit(main())
