"""Bounded asynchronous text-to-3D jobs. Inference/download never runs inside bpy.
Provider credentials live on this instance, not in browser commands.
"""
import asyncio
import ipaddress
import json
from pathlib import Path
import socket
import sqlite3
import time
import uuid
from aiohttp import TCPConnector,ClientSession,ClientTimeout
from aiohttp.abc import AbstractResolver

class PublicResolver(AbstractResolver):
    async def resolve(self,host,port=0,family=socket.AF_INET):
        values=await asyncio.get_running_loop().getaddrinfo(host,port,type=socket.SOCK_STREAM,family=family)
        results=[]
        for af,_,proto,_,address in values:
            ip=ipaddress.ip_address(address[0])
            if not ip.is_global:raise ValueError('Asset downloads require a public address')
            results.append({'hostname':host,'host':str(ip),'port':port,'family':af,'proto':proto,'flags':socket.AI_NUMERICHOST})
        return results
    async def close(self):pass

async def download_glb(url,destination,allowed_hosts):
    from urllib.parse import urlparse
    parsed=urlparse(url)
    if parsed.scheme!='https' or parsed.hostname not in allowed_hosts or parsed.username or parsed.port not in (None,443):raise ValueError('Asset URL must use an approved public HTTPS host')
    destination=Path(destination);temporary=destination.with_suffix('.part');total=0
    try:
        async with ClientSession(connector=TCPConnector(resolver=PublicResolver()),timeout=ClientTimeout(total=90)) as http:
            async with http.get(url,allow_redirects=False) as response:
                if response.status!=200:raise ValueError('Asset download failed')
                with temporary.open('wb') as output:
                    async for chunk in response.content.iter_chunked(65536):
                        total+=len(chunk)
                        if total>100*1024*1024:raise ValueError('Generated asset exceeds 100 MB')
                        output.write(chunk)
        with temporary.open('rb') as file:header=file.read(12)
        import struct
        if len(header)!=12 or header[:4]!=b'glTF' or struct.unpack('<II',header[4:])!=(2,total):raise ValueError('Provider must return a self-contained GLB 2.0 file')
        with temporary.open('rb') as file:
            file.seek(12);chunk=file.read(8)
            if len(chunk)!=8:raise ValueError('GLB is missing its JSON chunk')
            length,kind=struct.unpack('<I4s',chunk)
            if kind!=b'JSON' or length>5*1024*1024:raise ValueError('Invalid GLB JSON chunk')
            document=json.loads(file.read(length))
            for entry in document.get('buffers',[])+document.get('images',[]):
                if entry.get('uri') and not entry['uri'].startswith('data:'):raise ValueError('GLB must embed all image and buffer dependencies')
        temporary.replace(destination)
    finally:temporary.unlink(missing_ok=True)

class AssetJobs:
    def __init__(self,root,generate,stage,*,max_pending=16):
        self.root=Path(root);self.root.mkdir(parents=True,exist_ok=True);self.generate=generate;self.stage=stage;self.queue=asyncio.Queue(max_pending)
        self.db=sqlite3.connect(self.root/'jobs.sqlite3');self.db.execute('CREATE TABLE IF NOT EXISTS jobs (id TEXT PRIMARY KEY, owner TEXT NOT NULL, status TEXT NOT NULL, data TEXT NOT NULL)')
        # A crashed import cannot safely be replayed without canonical scene reconciliation.
        self.db.execute("UPDATE jobs SET status='recovery_required' WHERE status IN ('queued','generating','importing')");self.db.commit();self.task=None
    def start(self):self.task=asyncio.create_task(self.run())
    def submit(self,owner,prompt,camera_id,request_key):
        if not isinstance(prompt,str) or not 3<=len(prompt)<=2000:raise ValueError('Use a prompt between 3 and 2000 characters')
        if not isinstance(request_key,str) or not 8<=len(request_key)<=100:raise ValueError('Use a stable request key')
        identifier=str(uuid.uuid5(uuid.NAMESPACE_URL,owner+':'+request_key));existing=self.get(identifier,owner)
        if existing:
            if existing['prompt']!=prompt or existing['camera_id']!=camera_id:raise ValueError('Request key already used for a different asset')
            return existing
        if self.queue.full():raise ValueError('This instance asset generation queue is full')
        data={'id':identifier,'prompt':prompt,'camera_id':camera_id,'created_at':time.time()}
        self.db.execute('INSERT INTO jobs VALUES (?,?,?,?)',(identifier,owner,'queued',json.dumps(data)));self.db.commit();self.queue.put_nowait((owner,data));return {**data,'status':'queued'}
    def get(self,identifier,owner):
        row=self.db.execute('SELECT status,data FROM jobs WHERE id=? AND owner=?',(identifier,owner)).fetchone()
        return {**json.loads(row[1]),'status':row[0]} if row else None
    def update(self,data,status):self.db.execute('UPDATE jobs SET status=?,data=? WHERE id=?',(status,json.dumps(data),data['id']));self.db.commit()
    async def run(self):
        while True:
            owner,data=await self.queue.get()
            try:
                self.update(data,'generating');asset=await self.generate(data)
                self.update(data,'importing');data['result']=await self.stage(owner,data,asset);self.update(data,'ready')
            except asyncio.CancelledError:
                self.update(data,'recovery_required');raise
            except Exception as error:data['error']=str(error)[:500];self.update(data,'failed')
            finally:self.queue.task_done()
    async def close(self):
        if self.task:self.task.cancel();await asyncio.gather(self.task,return_exceptions=True)
        self.db.close()
