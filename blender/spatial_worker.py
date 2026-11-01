"""Persistent Blender main-thread worker. JSON commands arrive from an AsyncIO sidecar.

No network clients, Python threads or async bpy calls run in this process. The
render fallback works under --background; the GPU viewport backend needs a real
GPU-backed VIEW_3D context and is selected explicitly by deployment configuration.
"""
import argparse
import base64
import zlib
import collections
import json
import math
import os
from pathlib import Path
import select
import struct
import sys
import time
import traceback

import bpy
from mathutils import Matrix, Quaternion, Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
from runner import stage_manifest
from spatial_asset_staging import stage_asset

PREFIX='@LIGHTEK@'
def emit(event):
    print(PREFIX+json.dumps(event,separators=(',',':'),allow_nan=False),flush=True)
def flat(matrix):return [matrix[row][column] for column in range(4) for row in range(4)]
def matrix(values):
    result=Matrix([[values[column*4+row] for column in range(4)] for row in range(4)])
    if any(abs(result[3][i])>1e-6 for i in range(3)) or abs(result[3][3]-1)>1e-6 or abs(result.determinant())<1e-8:
        raise ValueError('Camera matrix must be an invertible affine camera-to-world matrix')
    return result

class Worker:
    def __init__(self,manifest,output,width,height,fps,backend='render'):
        self.created=stage_manifest(manifest)
        self.scene=bpy.context.scene;self.output=Path(output);self.output.mkdir(parents=True,exist_ok=True)
        self.width=width;self.height=height;self.fps=fps;self.backend=backend
        self.revision=int(manifest.get('revision',0));self.frame=max(0,self.scene.frame_current-self.scene.frame_start);self.playback='paused';self.play_anchor_ns=0;self.play_anchor_frame=self.frame
        self.client_seq=0;self.frame_seq=0;self.frame_id=None;self.render_ms=0;self.samples=collections.deque(maxlen=61)
        self.streaming=False;self.pipe=None
        self.active_camera=next((key for key,obj in self.created.items() if obj==self.scene.camera),'default')
        if self.active_camera=='default':self.created['default']=self.scene.camera
        self.view_camera=None;self.dirty=True
        self.scene.render.resolution_x=width;self.scene.render.resolution_y=height;self.scene.render.resolution_percentage=100
        self.scene.render.image_settings.file_format='JPEG';self.scene.render.image_settings.quality=80
        self.scene.render.film_transparent=False
        if backend=='render':
            engine=os.environ.get('SPATIAL_RENDER_ENGINE','BLENDER_WORKBENCH')
            self.scene.render.engine=engine
            if engine=='CYCLES':self.scene.cycles.samples=1;self.scene.cycles.use_denoising=False
            if engine=='BLENDER_WORKBENCH':
                self.scene.display.shading.light='STUDIO';self.scene.display.shading.color_type='MATERIAL'
                self.scene.display.render_aa='FXAA'
        else:self.prepare_viewport()
    def prepare_viewport(self):
        import gpu
        if bpy.app.background:raise RuntimeError('Viewport capture requires a GPU-backed Blender window/context, not --background')
        self.area=next((area for area in bpy.context.screen.areas if area.type=='VIEW_3D'),None)
        if not self.area:raise RuntimeError('No VIEW_3D region is available')
        self.region=next(region for region in self.area.regions if region.type=='WINDOW')
        self.offscreen=gpu.types.GPUOffScreen(self.width,self.height,format='RGBA8')
        self.area.spaces.active.shading.type=os.environ.get('SPATIAL_VIEWPORT_SHADING','RENDERED')
    def resolve(self,identifier,camera=False):
        obj=self.created.get(str(identifier))
        if obj is None or (camera and obj.type!='CAMERA'):raise ValueError('Scene object is unavailable')
        return obj
    def apply(self,message):
        kind=message['type'];payload=message['payload'];self.client_seq=message['seq']
        if message['scene_revision']!=self.revision:raise ValueError('CONFLICT: scene revision changed')
        if kind=='CAMERA_UPDATE':
            source=self.resolve(payload['camera_id'],True);self.active_camera=payload['camera_id']
            if payload['mode']=='preview':
                if self.view_camera is None:
                    self.view_camera=bpy.data.objects.new('Lightek viewer camera',source.data.copy());self.scene.collection.objects.link(self.view_camera)
                self.view_camera.matrix_world=source.matrix_world.copy()
                old=self.view_camera.data;self.view_camera.data=source.data.copy();bpy.data.cameras.remove(old)
                target=self.view_camera
            else:target=source
            if 'camera_world_matrix' in payload:target.matrix_world=matrix(payload['camera_world_matrix'])
            if 'focal_length_mm' in payload:target.data.lens=payload['focal_length_mm']
            if 'lens_shift' in payload:target.data.shift_x,target.data.shift_y=payload['lens_shift']
            self.scene.camera=target
        elif kind=='ASSET_TRANSFORM':
            obj=self.resolve(payload['object_id']);x,y,z,w=payload['rotation_quaternion'];rotation=Quaternion((w,x,y,z))
            if rotation.magnitude<1e-8:raise ValueError('Quaternion must not be zero')
            if any(abs(value)<1e-6 or abs(value)>10000 for value in payload['scale']):raise ValueError('Use nonzero scale within ±10000')
            rotation.normalize();obj.matrix_world=Matrix.LocRotScale(Vector(payload['position']),rotation,Vector(payload['scale']))
        elif kind=='TIMELINE_SCRUB':
            frame=int(payload['frame']);absolute=self.scene.frame_start+frame
            if absolute!=payload['blender_frame'] or not self.scene.frame_start<=absolute<=self.scene.frame_end:raise ValueError('Timeline frame is outside this scene')
            expected=self.scene.render.fps/self.scene.render.fps_base;provided=payload['fps']['num']/payload['fps']['den']
            if abs(expected-provided)>0.001:raise ValueError('Timeline FPS differs from the canonical scene')
            self.frame=frame;self.playback=payload['playback_state'];self.play_anchor_ns=time.monotonic_ns();self.play_anchor_frame=frame;self.scene.frame_set(absolute)
        else:raise ValueError('Unsupported Blender command')
        bpy.context.view_layer.update();self.dirty=True
        if payload.get('mode')=='commit':self.revision=int(message.get('applied_revision',self.revision+1))
    def stage(self,command):
        path=Path(command['asset_path']).resolve()
        if not path.is_relative_to(self.output.resolve()):raise ValueError('Asset must be a prepared session file')
        options=command.get('options',{})
        result=stage_asset(path,camera_name=self.resolve(command['camera_id'],True).name,**options)
        root=bpy.data.objects[result['root']];identifier=str(command['object_id']);self.created[identifier]=root
        anchor=bpy.data.objects.new(result['root']+' rig anchor',None);self.scene.collection.objects.link(anchor);anchor.parent=root;anchor['lightek_anchor_kind']='rig'
        collision=bpy.data.objects.new(result['root']+' collision anchor',None);self.scene.collection.objects.link(collision);collision.parent=root;collision['lightek_anchor_kind']='collision';collision['collision_shape']='CONVEX_HULL'
        self.revision=int(command['revision']);self.dirty=True
        location,rotation,scale=root.matrix_world.decompose();result['transform']={'location':list(location),'rotation':[math.degrees(v) for v in rotation.to_euler('XYZ')],'scale':list(scale)}
        return result
    def state(self):
        elapsed=self.samples[-1]-self.samples[0] if len(self.samples)>1 else 0
        return {'worker_id':os.getpid(),'frame':self.frame,'blender_frame':self.scene.frame_current,'playback_state':self.playback,
                'render':{'status':('rendering' if self.dirty else 'ready') if self.frame_id else 'staged','frame_id':self.frame_id,'render_ms':self.render_ms,'rendered_fps':(len(self.samples)-1)/elapsed if elapsed else 0},
                'cameras':[{'id':key,'name':obj.name,'focal_length_mm':obj.data.lens,'camera_type':obj.data.type,'active':key==self.active_camera} for key,obj in self.created.items() if obj.type=='CAMERA'][:128],
                'active_layer_nodes':[{'id':key,'name':obj.name,'kind':obj.type,'visible':not obj.hide_viewport and not obj.hide_render} for key,obj in self.created.items()][:1000]}
    def render(self):
        if self.playback=='playing':
            elapsed=(time.monotonic_ns()-self.play_anchor_ns)/1e9
            absolute=min(self.scene.frame_end,self.scene.frame_start+self.play_anchor_frame+int(elapsed*self.scene.render.fps/self.scene.render.fps_base))
            self.scene.frame_set(absolute);self.frame=absolute-self.scene.frame_start
            if absolute==self.scene.frame_end:self.playback='paused'
        started=time.monotonic_ns();self.frame_seq+=1
        depth_payload=None
        if self.backend=='viewport':
            import gpu
            camera=self.scene.camera;projection=camera.calc_matrix_camera(bpy.context.evaluated_depsgraph_get(),x=self.width,y=self.height)
            with bpy.context.temp_override(area=self.area,region=self.region):
                self.offscreen.draw_view3d(self.scene,bpy.context.view_layer,self.area.spaces.active,self.region,camera.matrix_world.inverted(),projection,do_color_management=True)
            with self.offscreen.bind():
                color_buffer=gpu.state.active_framebuffer_get().read_color(0,0,self.width,self.height,4,0,'UBYTE')
                color_buffer.dimensions=self.width*self.height*4;pixels=bytes(color_buffer)
            # A bounded, camera-aligned depth pass travels with this exact color frame.
                raw_depth=gpu.state.active_framebuffer_get().read_depth(0,0,self.width,self.height)
                raw_depth.dimensions=[self.height,self.width]
                depth_width=min(160,self.width);depth_height=min(90,self.height)
                values=[float(raw_depth[min(self.height-1,y*self.height//depth_height)][min(self.width-1,x*self.width//depth_width)]) for y in range(depth_height) for x in range(depth_width)]
                packed=base64.b64encode(zlib.compress(struct.pack('<'+'f'*len(values),*values),1)).decode()
                if len(packed)<=48000:depth_payload={'encoding':'zlib-f32le','width':depth_width,'height':depth_height,'data':packed,'origin':'bottom-left','range':'opengl_0_1'}
            format='rgba-flipped';path=None
        else:
            path=self.output/f'frame-{self.frame_seq%3}.jpg';temporary=self.output/'rendering.jpg'
            self.scene.render.filepath=str(temporary);bpy.ops.render.render(write_still=True);temporary.replace(path);pixels=path.read_bytes();path.unlink();format='jpeg'
        finished=time.monotonic_ns();self.render_ms=(finished-started)/1e6;self.samples.append(finished/1e9);self.frame_id=str(self.frame_seq)
        cam=self.scene.camera;projection=cam.calc_matrix_camera(bpy.context.evaluated_depsgraph_get(),x=self.width,y=self.height)
        metadata={'event':'FRAME','format':format,'width':self.width,'height':self.height,'sequence':self.frame_seq,'captured_ns':finished,'captured_wall_ms':time.time()*1000,
              'request_seq':self.client_seq,'revision':self.revision,'frame':self.frame,'blender_frame':self.scene.frame_current,'camera_id':self.active_camera,'frame_id':self.frame_id,
              'view_matrix':flat(cam.matrix_world.inverted()),'projection_matrix':flat(projection),'camera_world_matrix':flat(cam.matrix_world),'focal_length_mm':cam.data.lens,
              'render_ms':self.render_ms,'rendered_fps':self.state()['render']['rendered_fps']}
        if depth_payload:metadata['depth']={**depth_payload,'frame_id':self.frame_id}
        if self.pipe:
            header=json.dumps(metadata,separators=(',',':')).encode();data=memoryview(struct.pack('!II',len(header),len(pixels))+header+pixels)
            while data:
                written=self.pipe.write(data)
                if not written:raise BrokenPipeError('Frame receiver closed')
                data=data[written:]
        else:emit(metadata)
        self.dirty=False

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--manifest',required=True);parser.add_argument('--output',required=True)
    parser.add_argument('--width',type=int,default=640);parser.add_argument('--height',type=int,default=360);parser.add_argument('--fps',type=int,default=60)
    parser.add_argument('--frame-pipe');parser.add_argument('--backend',choices=['render','viewport'],default='render')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    worker=Worker(json.loads(Path(args.manifest).read_text()),args.output,args.width,args.height,args.fps,args.backend)
    if args.frame_pipe:worker.pipe=open(args.frame_pipe,'wb',buffering=0)
    emit({'event':'READY','revision':worker.revision,'state':worker.state()})
    buffer=b'';next_frame=time.monotonic();running=True
    while running:
        ready,_,_=select.select([sys.stdin],[],[],max(0,min(.05,next_frame-time.monotonic())) if (worker.dirty or worker.streaming) else .05)
        if ready:
            chunk=os.read(sys.stdin.fileno(),65536)
            if not chunk:break
            buffer+=chunk
            if len(buffer)>512*1024:raise ValueError('Worker command buffer exceeded its limit')
            while b'\n' in buffer:
                line,buffer=buffer.split(b'\n',1)
                command={}
                try:
                    command=json.loads(line);request=command['request_id']
                    if command.get('op')=='CLOSE':running=False;break
                    if command.get('op')=='STREAM':worker.streaming=bool(command['active']);result=None
                    elif command.get('op')=='STAGE_ASSET':result=worker.stage(command)
                    else:result=worker.apply(command['message'])
                    emit({'event':'RESULT','request_id':request,'revision':worker.revision,'state':worker.state(),'result':result})
                except Exception as error:emit({'event':'ERROR','request_id':command.get('request_id'),'message':str(error)[:1000]})
        if running and (worker.dirty or worker.streaming) and time.monotonic()>=next_frame:
            worker.render();next_frame=time.monotonic()+max(0,1/args.fps-worker.render_ms/1000)
    if worker.pipe:worker.pipe.close()
    if hasattr(worker,'offscreen'):worker.offscreen.free()

if __name__=='__main__':
    try:main()
    except Exception as error:emit({'event':'FATAL','message':str(error)[:1000]});traceback.print_exc();raise
