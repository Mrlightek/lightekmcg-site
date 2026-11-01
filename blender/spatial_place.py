"""Calculate camera-framed placement from canonical camera definitions; no render required."""
import json,math,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from runner import stage_manifest
from spatial_asset_staging import stage_asset
import bpy
args=sys.argv[sys.argv.index('--')+1:]
manifest=json.loads(Path(args[0]).read_text());stage_manifest(manifest)
result=stage_asset(args[1],name='Generated asset')
root=bpy.data.objects[result['root']];position,rotation,scale=root.matrix_world.decompose()
Path(args[2]).write_text(json.dumps({'location':list(position),'rotation':[math.degrees(v) for v in rotation.to_euler('XYZ')],'scale':list(scale)}))
