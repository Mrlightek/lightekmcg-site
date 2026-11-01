"""Real H.264 WebRTC track, with bounded frames and RTP-correlated metadata.

The aiortc integration is pinned to 1.15.0. Metadata is attached at its RTP transport
boundary, after timestamp randomization, so the browser never guesses frame IDs.
"""
import asyncio
from collections import deque
from fractions import Fraction
import io
import json
import struct
import time
import av
import numpy as np
from PIL import Image
from aiortc import MediaStreamTrack
from aiortc.mediastreams import MediaStreamError
from aiortc.rtp import is_rtcp

class BlenderTrack(MediaStreamTrack):
    kind='video'
    def __init__(self,bridge,encoder='libx264',on_error=lambda text:None):
        super().__init__();self.bridge=bridge;self.encoder_name=encoder;self.codec=None;self.on_error=on_error
        self.sequence=0;self.origin=None;self.last_pts=-1;self.packets=deque();self.metadata=deque(maxlen=64);self.by_pts={};self.force_keyframe=True
    def _encode(self,metadata,pixels,pts):
        if metadata['format']=='jpeg':image=Image.open(io.BytesIO(pixels)).convert('RGB');frame=av.VideoFrame.from_image(image)
        else:
            array=np.frombuffer(pixels,np.uint8).reshape(metadata['height'],metadata['width'],4)
            if metadata['format']=='rgba-flipped':array=array[::-1]
            frame=av.VideoFrame.from_ndarray(np.ascontiguousarray(array),format='rgba')
        if self.codec is None:
            codec=self.codec=av.CodecContext.create(self.encoder_name,'w');codec.width=frame.width;codec.height=frame.height;codec.pix_fmt='yuv420p'
            codec.time_base=Fraction(1,90000);codec.framerate=Fraction(self.bridge.fps,1);codec.bit_rate=4000000;codec.gop_size=self.bridge.fps;codec.max_b_frames=0;codec.thread_count=1
            codec.options=({'preset':'p1','tune':'ull','zerolatency':'1','rc-lookahead':'0','bf':'0'} if self.encoder_name=='h264_nvenc' else {'preset':'ultrafast','tune':'zerolatency','bf':'0','sc_threshold':'0'})
            codec.open()
        codec=self.codec
        frame=frame.reformat(format='yuv420p');frame.pts=pts;frame.time_base=Fraction(1,90000)
        if self.force_keyframe:frame.pict_type=av.video.frame.PictureType.I;self.force_keyframe=False
        return codec.encode(frame)
    async def recv(self):
        while not self.packets:
            try:metadata,pixels=await self.bridge.next_frame(self.sequence)
            except Exception as error:raise MediaStreamError from error
            self.sequence=metadata['sequence'];self.origin=self.origin or metadata['captured_ns']
            pts=max(self.last_pts+1,(metadata['captured_ns']-self.origin)*90000//1000000000);self.last_pts=pts
            self.by_pts[pts]=metadata
            started=time.monotonic_ns()
            try:packets=await asyncio.to_thread(self._encode,metadata,pixels,pts)
            except Exception as error:
                self.on_error('Video encoder failed: '+str(error)[:500]);raise MediaStreamError from error
            for packet in packets:
                packet.time_base=Fraction(1,90000);meta=self.by_pts.pop(packet.pts,metadata)
                self.packets.append((packet,{**meta,'encode_ms':(time.monotonic_ns()-started)/1e6}))
            while len(self.by_pts)>64:self.by_pts.pop(next(iter(self.by_pts)))
        packet,metadata=self.packets.popleft();self.metadata.append(metadata);return packet
    def stop(self):
        super().stop();self.packets.clear();self.metadata.clear();self.by_pts.clear();self.codec=None


def bind_rtp_metadata(sender,track,send_metadata):
    """One video sender per peer. Pin/test aiortc before upgrading this isolated seam."""
    original=sender.transport._send_rtp;original_keyframe=sender._send_keyframe
    seen=set();history=deque()
    async def send(data):
        if len(data)>=12 and not is_rtcp(data):
            _,_,_,timestamp,ssrc=struct.unpack('!BBHII',data[:12])
            if ssrc==sender._ssrc and timestamp not in seen and track.metadata:
                metadata=track.metadata.popleft();seen.add(timestamp);history.append(timestamp)
                if len(history)>256:seen.discard(history.popleft())
                send_metadata({'type':'FRAME_META',**{key:value for key,value in metadata.items() if key not in {'path','pixels','received_ns'}},'rtp_timestamp':timestamp,'sent_wall_ms':time.time()*1000})
        await original(data)
    def request_keyframe():track.force_keyframe=True;original_keyframe()
    sender.transport._send_rtp=send;sender._send_keyframe=request_keyframe
    return lambda:setattr(sender.transport,'_send_rtp',original)
