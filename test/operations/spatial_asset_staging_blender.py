"""Run with Blender --background --factory-startup --python this_file."""
from pathlib import Path
import importlib.util
import os
import tempfile
import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("spatial_asset_staging", root / "blender/spatial_asset_staging.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
fixture = os.environ.get("STUDIO_VIEWPORT_FIXTURE", "/tmp/native-viewport-proof.glb")
camera = bpy.context.scene.camera
original_camera = camera
checks = 0
for projection in ["PERSP", "ORTHO"]:
    camera.data.type = projection
    camera.data.shift_x = .1
    result = module.stage_asset(fixture, screen_x=.2, screen_y=-.1, distance=6, fit_fraction=.5)
    group = bpy.data.objects[result["root"]]
    assert result["scale"] > 0 and bpy.context.scene.camera == original_camera
    for obj in group.children_recursive:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            screen = world_to_camera_view(bpy.context.scene, camera, obj.matrix_world @ Vector(corner))
            assert .02 < screen.x < .98 and .02 < screen.y < .98, (projection, tuple(screen))
    checks += 1
before = set(bpy.data.objects)
try:
    module.stage_asset(fixture, distance=float("nan"))
    raise AssertionError("NaN was accepted")
except ValueError:
    assert set(bpy.data.objects) == before
checks += 1
with tempfile.TemporaryDirectory() as temporary:
    obj_path = Path(temporary) / "triangle.obj"
    obj_path.write_text("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n")
    result = module.stage_asset(obj_path, color=(.1,.2,.3,1))
    meshes = [obj for obj in bpy.data.objects[result["root"]].children_recursive if obj.type == "MESH"]
    assert meshes and meshes[0].data.materials
    color = meshes[0].data.materials[0].node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value
    assert all(abs(a-b) < 1e-6 for a,b in zip(color,(.1,.2,.3,1)))
    checks += 1
    empty_path = Path(temporary) / "empty.gltf"
    empty_path.write_text('{"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[]}],"nodes":[]}')
    before = set(bpy.data.objects)
    try:
        module.stage_asset(empty_path)
        raise AssertionError("An empty asset was accepted")
    except ValueError:
        assert set(bpy.data.objects) == before and bpy.context.scene.camera == original_camera
    checks += 1
print("STUDIO_TEXT_TO_STAGE_PASS", checks, "gltf obj default_material perspective orthographic shifted_lens framing invalid_parameters rollback camera_preserved")
