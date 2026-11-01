"""Existing per-instance Docker dependency-worker model; Rails stays in Passenger."""
import os
from pathlib import Path

def container_launcher(image,backend):
    def launch(command,root):
        script=Path(__file__).resolve().parents[2]/'blender'
        engine_args=command[1:];engine_args[engine_args.index('--python')+1]='/engine/spatial_worker.py'
        args=['docker','run','--rm','--init','--network','none','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges','--pids-limit','256','--memory',os.environ.get('SPATIAL_WORKER_MEMORY','4g'),'--cpus',os.environ.get('SPATIAL_WORKER_CPUS','2'),'--user',f'{os.getuid()}:{os.getgid()}','--tmpfs','/tmp:rw,nosuid,size=512m','-v',f'{root}:{root}:rw','-v',f'{script}:/engine:ro']
        if backend=='viewport':
            display=os.environ.get('DISPLAY');authority=os.environ.get('SPATIAL_XAUTHORITY')
            if not display or not authority:raise ValueError('GPU viewport container needs DISPLAY and SPATIAL_XAUTHORITY')
            args+=['--gpus','all','-e','NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics,video,display','-e',f'DISPLAY={display}','-e','XAUTHORITY=/run/lightek-xauth','-v','/tmp/.X11-unix:/tmp/.X11-unix:ro','-v',f'{authority}:/run/lightek-xauth:ro']
        for name in ['SPATIAL_RENDER_ENGINE','SPATIAL_VIEWPORT_SHADING']:
            if name in os.environ:args+=['-e',f'{name}={os.environ[name]}']
        return args+[image,'blender',*engine_args]
    return launch
