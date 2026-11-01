"""Async process supervisor; Blender owns bpy, this process owns sockets/encoding."""
import asyncio
import json
import os
from pathlib import Path
import signal
import struct
import time
import uuid

class BlenderBridge:
    def __init__(self,root,manifest,*,blender='blender',backend='render',width=640,height=360,fps=60,launcher=None):
        self.root=Path(root);self.manifest=manifest;self.blender=blender;self.backend=backend
        self.width=width;self.height=height;self.fps=fps;self.launcher=launcher
        self.process=None;self.tasks=[];self.waiters={};self.ready=asyncio.Event();self.changed=asyncio.Condition()
        self.latest=None;self.state=None;self.error=None;self.closed=False;self.frame_count=0
        self.request_lock=asyncio.Lock()
    async def start(self):
        self.root.mkdir(parents=True,exist_ok=True);os.chmod(self.root,0o700)
        manifest_path=self.root/'manifest.json';manifest_path.write_text(json.dumps(self.manifest))
        pipe=self.root/'frames.pipe'
        if pipe.exists():pipe.unlink()
        os.mkfifo(pipe,0o600)
        script=Path(__file__).resolve().parents[2]/'blender/spatial_worker.py'
        command=[self.blender]
        if self.backend!='viewport':command+=['--background']
        command+=['--factory-startup','--disable-autoexec','--python-exit-code','1','--python',str(script),'--','--manifest',str(manifest_path),'--output',str(self.root),'--frame-pipe',str(pipe),'--width',str(self.width),'--height',str(self.height),'--fps',str(self.fps),'--backend',self.backend]
        if self.launcher:command=self.launcher(command,self.root)
        self.tasks.append(asyncio.create_task(self._frames(pipe)))
        try:self.process=await asyncio.create_subprocess_exec(*command,stdin=asyncio.subprocess.PIPE,stdout=asyncio.subprocess.PIPE,stderr=asyncio.subprocess.DEVNULL,start_new_session=True,limit=256*1024)
        except BaseException:
            await self.close();raise
        self.tasks.append(asyncio.create_task(self._events()))
        try:
            await asyncio.wait_for(self.ready.wait(),45)
            if self.error:raise RuntimeError(self.error)
        except BaseException:
            await self.close();raise
        return self
    async def _events(self):
        try:
            while line:=await self.process.stdout.readline():
                if not line.startswith(b'@LIGHTEK@'):continue
                event=json.loads(line[len(b'@LIGHTEK@'):])
                if event['event']=='READY':self.state={**event['state'],'revision':event['revision']};self.ready.set()
                elif event['event']=='FATAL':self.error=event['message'];self.ready.set()
                elif event.get('request_id') in self.waiters:
                    future=self.waiters.pop(event['request_id'])
                    if future.done():continue
                    if event['event']=='ERROR':future.set_exception(ValueError(event['message']))
                    else:self.state={**event['state'],'revision':event['revision']};future.set_result(event)
        finally:
            self.error=self.error or 'Blender worker exited';self.ready.set()
            for future in self.waiters.values():
                if not future.done():future.set_exception(RuntimeError(self.error))
            self.waiters.clear()
            async with self.changed:self.changed.notify_all()
    @staticmethod
    def _read_frame(stream):
        header=stream.read(8)
        if not header:raise EOFError('Frame pipe closed')
        if len(header)!=8:raise ValueError('Truncated frame header')
        meta_size,pixel_size=struct.unpack('!II',header)
        if not 1<=meta_size<=65536 or not 1<=pixel_size<=16*1024*1024:raise ValueError('Invalid frame size')
        meta=stream.read(meta_size);pixels=stream.read(pixel_size)
        if len(meta)!=meta_size or len(pixels)!=pixel_size:raise ValueError('Truncated frame')
        return json.loads(meta),pixels
    async def _frames(self,pipe):
        stream=None
        try:
            stream=await asyncio.to_thread(open,pipe,'rb')
            while not self.closed:
                metadata,pixels=await asyncio.to_thread(self._read_frame,stream)
                if metadata['width']!=self.width or metadata['height']!=self.height:raise ValueError('Frame dimensions changed unexpectedly')
                metadata['received_ns']=time.monotonic_ns();self.latest=(metadata,pixels);self.frame_count+=1
                async with self.changed:self.changed.notify_all()
        except asyncio.CancelledError:pass
        except (EOFError,OSError,ValueError) as error:
            if not self.closed:
                self.error=str(error)
                async with self.changed:self.changed.notify_all()
        finally:
            if stream:stream.close()
    async def next_frame(self,after):
        async with self.changed:
            await asyncio.wait_for(self.changed.wait_for(lambda:self.closed or self.error or (self.latest and self.latest[0]['sequence']>after)),30)
        if self.closed or self.error:raise RuntimeError(self.error or 'Session closed')
        return self.latest
    async def request(self,command,timeout=30):
        async with self.request_lock:
            if self.closed or not self.process or self.process.returncode is not None:raise RuntimeError('Blender session is unavailable')
            request_id=str(uuid.uuid4());command={**command,'request_id':request_id}
            future=asyncio.get_running_loop().create_future();self.waiters[request_id]=future
            try:
                self.process.stdin.write(json.dumps(command,allow_nan=False).encode()+b'\n');await self.process.stdin.drain()
                return await asyncio.wait_for(future,timeout)
            finally:self.waiters.pop(request_id,None)
    async def close(self):
        if self.closed:return
        self.closed=True
        if self.process and self.process.returncode is None:
            self.process.stdin.close()
            try:await asyncio.wait_for(self.process.wait(),3)
            except asyncio.TimeoutError:
                os.killpg(self.process.pid,signal.SIGTERM)
                try:await asyncio.wait_for(self.process.wait(),3)
                except asyncio.TimeoutError:os.killpg(self.process.pid,signal.SIGKILL);await self.process.wait()
        # Unblock a FIFO reader if worker failed before opening its write end.
        pipe=self.root/'frames.pipe'
        try:fd=os.open(pipe,os.O_WRONLY|os.O_NONBLOCK);os.close(fd)
        except OSError:pass
        for task in self.tasks:task.cancel()
        await asyncio.gather(*self.tasks,return_exceptions=True)
        async with self.changed:self.changed.notify_all()
        pipe.unlink(missing_ok=True)
