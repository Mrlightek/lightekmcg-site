"""Lightek's authenticated persistent Blender / WebRTC sidecar.

Run with python -m services.spatial.server. Rails authorizes session creation;
browser control sockets use short-lived, scene-bound tickets. No bpy calls run here.
"""
import asyncio
import base64
from collections import OrderedDict,deque
import hashlib
import hmac
import json
import os
from pathlib import Path
import secrets
import time
import uuid

from aiohttp import web,ClientSession,ClientTimeout,WSMsgType
from aiortc import RTCPeerConnection,RTCSessionDescription,RTCConfiguration,RTCIceServer
from aiortc.sdp import candidate_from_sdp
from .bridge import BlenderBridge
from .media import BlenderTrack,bind_rtp_metadata
from .protocol import parse_message,durable,preview_key


def b64(value):return base64.urlsafe_b64encode(value).rstrip(b'=').decode()
def ticket(secret,claims):
    data=b64(json.dumps(claims,separators=(',',':')).encode());return data+'.'+b64(hmac.new(secret.encode(),data.encode(),hashlib.sha256).digest())
def verify(secret,value):
    data,signature=value.split('.')
    if not hmac.compare_digest(signature,b64(hmac.new(secret.encode(),data.encode(),hashlib.sha256).digest())):raise ValueError('Invalid session ticket')
    claims=json.loads(base64.urlsafe_b64decode(data+'='*(-len(data)%4)))
    if claims['exp']<time.time():raise ValueError('Session ticket expired')
    return claims

class SpatialSession:
    def __init__(self,service,identifier,owner,scene_id,bridge):
        self.service=service;self.id=identifier;self.owner=owner;self.scene_id=scene_id;self.bridge=bridge
        self.epoch=str(uuid.uuid4());self.server_seq=0;self.clients=set();self.last_activity=time.monotonic();self.receipts=OrderedDict();self.watermarks={}
        self.commits=deque();self.previews=OrderedDict();self.wakeup=asyncio.Event();self.peer=None;self.channel=None;self.track=None;self.closed=False
        self.pump=asyncio.create_task(self._pump());self.signal_lock=asyncio.Lock();self.ice=[];self.frame_sent={};self.stats={'frame_round_trip_ms':None};self.monitor=asyncio.create_task(self._monitor())
    async def failed(self,text):
        for ws in list(self.clients):
            try:await self.error(ws,{},'WORKER_FAILED',text)
            except Exception:pass
        if self.peer:await self.peer.close()
    async def _monitor(self):
        await self.bridge.process.wait()
        if not self.closed:await self.failed(self.bridge.error or 'Blender worker exited. Reopen the saved scene.')
    def envelope(self,kind,payload):
        self.server_seq+=1
        return {'v':1,'type':kind,'session_id':self.id,'message_id':str(uuid.uuid4()),'seq':self.server_seq,'scene_revision':self.bridge.state.get('revision',self.bridge.manifest.get('revision',0)),'payload':payload}
    async def send(self,ws,kind,payload):
        if not ws.closed:await ws.send_json(self.envelope(kind,payload))
    async def state(self,ws,client_id):
        payload={**{key:value for key,value in self.bridge.state.items() if key!='revision'},'server_epoch':self.epoch,'ready':True,'last_client_seq':self.watermarks.get(client_id,0),
                 'recent_receipts':[key[1] for key in self.receipts if key[0]==client_id][-256:]}
        await self.send(ws,'SERVER_STATE',payload)
    async def error(self,ws,message,code,text):
        await self.send(ws,'ERROR',{'command_id':message.get('message_id'),'code':code,'message':text[:1000],'revision':self.bridge.state.get('revision',0)})
    async def enqueue(self,ws,client_id,message):
        self.last_activity=time.monotonic();key=(client_id,message['message_id']);fingerprint=hashlib.sha256(json.dumps(message,sort_keys=True).encode()).hexdigest()
        if key in self.receipts:
            previous=self.receipts[key]
            if previous['hash']!=fingerprint:return await self.error(ws,message,'INVALID','A message ID cannot be reused with different values')
            return await self.send(ws,'ACK',{'command_id':message['message_id'],'status':'duplicate','revision':previous['revision']})
        if durable(message):
            if message['seq']<=self.watermarks.get(client_id,-1):return await self.error(ws,message,'RECOVERY_REQUIRED','Receipt history expired. Refresh canonical scene state before reconciling this command.')
            if len(self.commits)>=64:return await self.error(ws,message,'BUSY','The persistent edit queue is full; retain the edit locally and retry.')
            self.commits.append((ws,client_id,message,fingerprint))
        else:
            key=(client_id,*preview_key(message))
            if key not in self.previews and len(self.previews)>=32:return await self.error(ws,message,'BUSY','Too many preview targets')
            self.previews[key]=(ws,client_id,message,fingerprint)
        self.wakeup.set()
    async def _pump(self):
        while not self.closed:
            await self.wakeup.wait()
            if self.commits:ws,client_id,message,fingerprint=self.commits.popleft()
            elif self.previews:_,(ws,client_id,message,fingerprint)=self.previews.popitem(last=False)
            else:self.wakeup.clear();continue
            try:
                if durable(message) and (client_id,message['message_id']) in self.receipts:
                    receipt=self.receipts[(client_id,message['message_id'])]
                    if receipt['hash']!=fingerprint:raise ValueError('Message ID reused with different values')
                    await self.send(ws,'ACK',{'command_id':message['message_id'],'status':'duplicate','revision':receipt['revision']});continue
                if not durable(message) and message['scene_revision']!=self.bridge.state['revision']:
                    await self.send(ws,'ACK',{'command_id':message['message_id'],'status':'superseded','revision':self.bridge.state['revision']});continue
                applied=await self.service.commit(self,message) if durable(message) else None
                worker_message={**message}
                if applied is not None:worker_message['applied_revision']=applied
                result=await self.bridge.request({'message':worker_message})
                revision=result['revision'];self.bridge.state['revision']=revision
                if durable(message):
                    self.receipts[(client_id,message['message_id'])]={'hash':fingerprint,'revision':revision}
                    self.watermarks[client_id]=max(message['seq'],self.watermarks.get(client_id,0))
                    while len(self.receipts)>2048:self.receipts.popitem(last=False)
                await self.send(ws,'ACK',{'command_id':message['message_id'],'status':'applied','revision':revision})
                await self.state(ws,client_id)
            except Exception as error:
                code='CONFLICT' if 'CONFLICT' in str(error) or 'revision' in str(error).lower() else 'WORKER_FAILED'
                await self.error(ws,message,code,str(error))
    async def offer(self,ws,payload):
        async with self.signal_lock:
            if self.peer:await self.peer.close()
            servers=[RTCIceServer(**item) for item in self.service.ice_servers]
            peer=self.peer=RTCPeerConnection(RTCConfiguration(iceServers=servers))
            track=self.track=BlenderTrack(self.bridge,self.service.encoder,on_error=lambda text:asyncio.create_task(self.failed(text)))
            sender=peer.addTrack(track)
            transceiver=next(t for t in peer.getTransceivers() if t.sender==sender)
            capabilities=sender.getCapabilities('video');transceiver.setCodecPreferences([codec for codec in capabilities.codecs if codec.mimeType.lower()=='video/h264'])
            bind_rtp_metadata(sender,track,self.media_metadata)
            @peer.on('datachannel')
            def channel_open(channel):
                self.channel=channel
                @channel.on('message')
                def data(value):
                    if not isinstance(value,str) or len(value)>4096:return
                    try:
                        message=json.loads(value);now=time.monotonic_ns();self.last_activity=time.monotonic()
                        if message.get('type')=='PING':channel.send(json.dumps({'type':'PONG','id':message.get('id'),'sent_ms':message.get('sent_ms'),'server_recv_ms':time.time()*1000,'server_send_ms':time.time()*1000}))
                        elif message.get('type')=='FRAME_PRESENTED':
                            captured=self.frame_sent.get(str(message.get('frame_id')))
                            if captured:
                                elapsed=(now-captured)/1e6;self.stats['frame_round_trip_ms']=elapsed
                                channel.send(json.dumps({'type':'FRAME_ACK','frame_id':message['frame_id'],'frame_round_trip_ms':elapsed}))
                    except (ValueError,TypeError):pass
            @peer.on('connectionstatechange')
            async def changed():
                if peer is self.peer and peer.connectionState in {'failed','closed'}:
                    track.stop()
                    try:await self.bridge.request({'op':'STREAM','active':False})
                    except Exception:pass
            await peer.setRemoteDescription(RTCSessionDescription(sdp=payload['sdp'],type='offer'))
            for candidate in self.ice:await peer.addIceCandidate(candidate)
            self.ice.clear()
            await self.bridge.request({'op':'STREAM','active':True})
            await peer.setLocalDescription(await peer.createAnswer())
            await self.send(ws,'SDP_ANSWER',{'sdp':peer.localDescription.sdp,'type':'answer'})
    async def candidate(self,payload):
        value=payload.get('candidate')
        candidate=candidate_from_sdp(value.removeprefix('candidate:')) if value else None
        if candidate:candidate.sdpMid=payload.get('sdpMid');candidate.sdpMLineIndex=payload.get('sdpMLineIndex')
        if self.peer and self.peer.remoteDescription:await self.peer.addIceCandidate(candidate)
        elif len(self.ice)<128:self.ice.append(candidate)
    def media_metadata(self,metadata):
        self.frame_sent[str(metadata['frame_id'])]=metadata['captured_ns']
        while len(self.frame_sent)>256:self.frame_sent.pop(next(iter(self.frame_sent)))
        if self.channel and self.channel.readyState=='open' and self.channel.bufferedAmount<128*1024:
            self.channel.send(json.dumps(metadata,separators=(',',':'),allow_nan=False))
    async def close(self):
        if self.closed:return
        self.closed=True;self.pump.cancel();self.monitor.cancel()
        if self.peer:await self.peer.close()
        await self.bridge.close();await asyncio.gather(self.pump,self.monitor,return_exceptions=True)
        await asyncio.to_thread(__import__('shutil').rmtree,self.bridge.root,True)
        for ws in list(self.clients):await ws.close(code=1001,message=b'Scene session closed')

class SpatialService:
    def __init__(self,*,root,secret,blender='blender',backend='render',encoder='libx264',origins=(),ice_servers=(),commit_callback=None,launcher=None):
        if len(secret)<32:raise ValueError('Use a service secret of at least 32 characters')
        self.root=Path(root).resolve();self.root.mkdir(parents=True,exist_ok=True);self.secret=secret;self.blender=blender;self.backend=backend;self.encoder=encoder
        self.origins=set(origins);self.ice_servers=list(ice_servers);self.commit_callback=commit_callback;self.launcher=launcher;self.sessions={};self.http=None;self.creation_lock=asyncio.Lock()
    def auth(self,request):
        if not hmac.compare_digest(request.headers.get('Authorization',''),'Bearer '+self.secret):raise web.HTTPUnauthorized()
    async def commit(self,session,message):
        if message['scene_revision']!=session.bridge.state.get('revision',0):raise ValueError('CONFLICT: scene revision changed')
        if self.commit_callback:return await self.commit_callback(session,message)
        if os.environ.get('SPATIAL_COMMIT_URL'):
            async with self.http.post(os.environ['SPATIAL_COMMIT_URL'],json={'session_id':session.id,**session.owner,'scene_id':session.scene_id,'command':message},headers={'Authorization':'Bearer '+self.secret}) as response:
                result=await response.json()
                if response.status!=200:raise ValueError(result.get('error','CONFLICT: canonical scene changed'))
                return result['revision']
        raise ValueError('Durable changes require the canonical Rails commit endpoint; preview controls remain available')
    def credentials(self,session):
        claims={'sid':session.id,'uid':session.owner['user_id'],'scene_id':session.scene_id,'exp':int(time.time()+300)}
        return {'session_id':session.id,'ticket':ticket(self.secret,claims),'expires_at':claims['exp'],'ice_servers':self.ice_servers,'backend':self.backend,'encoder':self.encoder}
    async def create(self,request):
        async with self.creation_lock:return await self._create(request)
    async def _create(self,request):
        self.auth(request);data=await request.json();identifier=data.get('session_id',str(uuid.uuid4()))
        try:uuid.UUID(identifier)
        except ValueError:raise web.HTTPBadRequest(text='Invalid session identifier')
        owner={'user_id':int(data['user_id']),'site_id':data.get('site_id')};scene_id=int(data['manifest']['scene']['id'])
        if identifier in self.sessions:
            session=self.sessions[identifier]
            if session.owner!=owner:raise web.HTTPForbidden()
            return web.json_response(self.credentials(session))
        if len(self.sessions)>=int(os.environ.get('SPATIAL_MAX_SESSIONS','2')):raise web.HTTPServiceUnavailable(text='This instance has no free preview worker')
        directory=self.root/identifier;manifest=data['manifest']
        for container,key in [(manifest,'native_template_path')]+[(obj.get('definition',{}),'asset_path') for obj in manifest['scene'].get('objects',[])]:
            if container.get(key):
                path=(directory/container[key]).resolve()
                if not path.is_relative_to(directory.resolve()) or not path.is_file():raise web.HTTPBadRequest(text='Prepared scene dependency is missing')
                container[key]=str(path)
        bridge=BlenderBridge(directory,manifest,blender=self.blender,backend=self.backend,width=int(os.environ.get('SPATIAL_WIDTH','640')),height=int(os.environ.get('SPATIAL_HEIGHT','360')),fps=int(os.environ.get('SPATIAL_FPS','60')),launcher=self.launcher)
        try:await bridge.start()
        except Exception as error:raise web.HTTPServiceUnavailable(text=str(error))
        session=SpatialSession(self,identifier,owner,scene_id,bridge);bridge.state['revision']=int(manifest.get('revision',0));self.sessions[identifier]=session
        return web.json_response(self.credentials(session),status=201)
    async def ticket_handler(self,request):
        self.auth(request);data=await request.json();session=self.sessions.get(request.match_info['sid'])
        if not session or session.owner!={'user_id':int(data['user_id']),'site_id':data.get('site_id')}:raise web.HTTPNotFound()
        session.last_activity=time.monotonic();return web.json_response(self.credentials(session))
    async def close_handler(self,request):
        self.auth(request);data=await request.json();session=self.sessions.get(request.match_info['sid'])
        if session and session.owner=={'user_id':int(data['user_id']),'site_id':data.get('site_id')}:await session.close();self.sessions.pop(session.id,None)
        return web.json_response({'closed':True})
    async def websocket(self,request):
        if self.origins and request.headers.get('Origin') not in self.origins:raise web.HTTPForbidden()
        ws=web.WebSocketResponse(heartbeat=15,max_msg_size=65536,compress=False);await ws.prepare(request);session=None;signal_tasks=set()
        try:
            hello=await asyncio.wait_for(ws.receive_str(),5);message=parse_message(hello)
            if message['type']!='HELLO':raise ValueError('Authenticate with HELLO first')
            claims=verify(self.secret,message['payload']['ticket']);session=self.sessions.get(claims['sid'])
            if not session or claims['uid']!=session.owner['user_id'] or claims['scene_id']!=session.scene_id or message['session_id']!=session.id:raise ValueError('Session access denied')
            client_id=message['payload']['client_id'];session.clients.add(ws);await session.state(ws,client_id)
            async for event in ws:
                if event.type!=WSMsgType.TEXT:continue
                try:
                    message=parse_message(event.data)
                    if message['session_id']!=session.id:raise ValueError('Wrong session')
                    kind=message['type'];session.last_activity=time.monotonic()
                    if kind=='PING':await session.send(ws,'PONG',{})
                    elif kind=='SDP_OFFER':
                        async def answer(command):
                            try:await session.offer(ws,command['payload'])
                            except Exception as error:await session.error(ws,command,'WORKER_FAILED',str(error))
                        task=asyncio.create_task(answer(message));signal_tasks.add(task);task.add_done_callback(signal_tasks.discard)
                    elif kind=='ICE_CANDIDATE':await session.candidate(message['payload'])
                    elif kind!='HELLO':await session.enqueue(ws,client_id,message)
                except Exception as error:await session.error(ws,message if isinstance(message,dict) else {},'INVALID',str(error))
        except Exception:
            await ws.close(code=1008,message=b'Session authentication failed')
        finally:
            if session:session.clients.discard(ws)
            for task in signal_tasks:task.cancel()
            await asyncio.gather(*signal_tasks,return_exceptions=True)
        return ws
    def app(self):
        app=web.Application(client_max_size=1024*1024)
        app.router.add_post('/sessions',self.create);app.router.add_post('/sessions/{sid}/ticket',self.ticket_handler);app.router.add_post('/sessions/{sid}/close',self.close_handler)
        async def health(request):return web.json_response({'ready':bool(__import__('shutil').which('docker' if self.launcher else self.blender)),'backend':self.backend,'encoder':self.encoder,'sessions':len(self.sessions)})
        app.router.add_get('/ws',self.websocket);app.router.add_get('/health',health)
        async def startup(app):self.http=ClientSession(timeout=ClientTimeout(total=30));app['sweeper']=asyncio.create_task(sweep())
        async def sweep():
            while True:
                await asyncio.sleep(15)
                for sid,session in list(self.sessions.items()):
                    if time.monotonic()-session.last_activity>120:await session.close();self.sessions.pop(sid,None)
        async def cleanup(app):
            app['sweeper'].cancel();await asyncio.gather(app['sweeper'],return_exceptions=True)
            await asyncio.gather(*(session.close() for session in self.sessions.values()),return_exceptions=True);await self.http.close()
        app.on_startup.append(startup);app.on_cleanup.append(cleanup);return app

if __name__=='__main__':
    from .launcher import container_launcher
    image=os.environ.get('SPATIAL_CONTAINER_IMAGE');backend=os.environ.get('SPATIAL_BACKEND','render')
    if not image and os.environ.get('SPATIAL_ALLOW_NATIVE')!='1':raise RuntimeError('Configure SPATIAL_CONTAINER_IMAGE or explicitly allow a trusted native Blender runtime')
    launcher=container_launcher(image,backend) if image else None
    service=SpatialService(root=os.environ['STUDIO_SPATIAL_ROOT'],secret=os.environ['STUDIO_SPATIAL_SECRET'],blender=os.environ.get('BLENDER_BIN','blender'),backend=os.environ.get('SPATIAL_BACKEND','render'),encoder=os.environ.get('SPATIAL_ENCODER','libx264'),origins=json.loads(os.environ.get('SPATIAL_ORIGINS','[]')),ice_servers=json.loads(os.environ.get('SPATIAL_ICE_SERVERS','[]')),launcher=launcher)
    web.run_app(service.app(),host='127.0.0.1',port=int(os.environ.get('STUDIO_SPATIAL_PORT','8095')),access_log=None)
