"""Run with blender -b --factory-startup --python-exit-code 1 --python this_file."""
import base64
import importlib.util
import json
import struct
from pathlib import Path
from tempfile import TemporaryDirectory

import bpy

script = Path(__file__).resolve().parents[2] / "lib/scripts/studio_scene_render.py"
spec = importlib.util.spec_from_file_location("render", script)
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


def cube(name, x, collection):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, 0, 0))
    obj = bpy.context.object
    obj.name = name
    if collection not in obj.users_collection:
        for owner in list(obj.users_collection):
            owner.objects.unlink(obj)
        collection.objects.link(obj)
    return obj


def fixture(root):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.name = "A render source"
    hidden = bpy.data.collections.new("Hidden in render")
    hidden.hide_render = True
    scene.collection.children.link(hidden)
    cube("HiddenMesh", 9, hidden)

    excluded = bpy.data.collections.new("Excluded from render layer")
    scene.collection.children.link(excluded)
    cube("ExcludedMesh", 11, excluded)
    bpy.context.view_layer.layer_collection.children[excluded.name].exclude = True

    viewport = bpy.data.collections.new("Viewport only exclusion")
    viewport.hide_viewport = True
    scene.collection.children.link(viewport)
    cube("VisibleMesh", 2, viewport).hide_viewport = True
    cube("Studio floor", 15, scene.collection)
    cube("Flagged floor", 17, scene.collection)["lightek_character_floor"] = True
    cube("Object render hidden", 19, scene.collection).hide_render = True
    other = bpy.data.scenes.new("Z alternate scene")
    cube("WrongScene", 13, other.collection)

    animated = cube("AnimatedMesh", 3, scene.collection)
    animated.keyframe_insert(data_path="location", frame=1)
    animated.location.x = 5
    animated.keyframe_insert(data_path="location", frame=12)
    bpy.ops.object.armature_add()
    rig = bpy.context.object
    rig.name = "Rig"
    rig.keyframe_insert(data_path="location", frame=1)
    rig.location.x = 7
    rig.keyframe_insert(data_path="location", frame=12)
    action = rig.animation_data.action
    action.name = "Walk"
    action.use_fake_user = True
    rig.animation_data_clear()
    rig.location.x = 0
    cube("RigMesh", 0, scene.collection).parent = rig
    scene.frame_set(1)
    (root / "inputs").mkdir()
    bpy.ops.wm.save_as_mainfile(filepath=str(root / "inputs/1.blend"))


def rendered_geometry(objects):
    # Compare evaluated world-space vertex positions. A glTF round trip can
    # split vertices for normals/UVs, so compare unique positions.
    bpy.context.view_layer.update()
    return {
        obj.name.split(" · pose")[0]: sorted({
            tuple(round(coord, 4) for coord in obj.matrix_world @ vertex.co)
            for vertex in obj.data.vertices
        })
        for obj in objects if obj.type == "MESH"
    }


with TemporaryDirectory() as tmp:
    root = Path(tmp)
    fixture(root)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = 30
    parent = worker.empty(bpy, "Render source")
    live = worker.import_model(bpy, root / "inputs/1.blend", parent, {"starter": True})
    assert {obj.name for obj in live if obj.type == "MESH" and not obj.hide_render} == {"VisibleMesh", "AnimatedMesh", "RigMesh"}
    scene.frame_set(12)
    expected = rendered_geometry(obj for obj in live if not obj.hide_render)
    assert expected["AnimatedMesh"][0][0] == 4.5

    bpy.ops.wm.read_factory_settings(use_empty=True)
    parent = worker.empty(bpy, "Render source")
    baked = worker.import_model(bpy, root / "inputs/1.blend", parent, {"starter": True, "pose_frame": 12})
    assert rendered_geometry(baked) == expected

    worker.preview(bpy, {"source": "inputs/1.blend", "starter": True, "pose_frame": 12, "fps": 30}, root)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(root / "preview.glb"))
    assert rendered_geometry(bpy.context.scene.objects) == expected
    assert not list(bpy.data.actions)

    worker.preview(bpy, {"source": "inputs/1.blend", "starter": True, "pose_frame": 12, "fps": 24, "action": "Walk"}, root)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(root / "preview.glb"))
    assert rendered_geometry(bpy.context.scene.objects)["RigMesh"][0][0] == 6.5

    # GLTFLoader picks the declared scene while Blender imports every root.
    # The worker must exclude the alternate mesh in both GLTF and GLB.
    vertices = struct.pack("<9f", 0, 0, 0, 1, 0, 0, 0, 1, 0)
    document = {
        "asset": {"version": "2.0"},
        "scene": 1,
        "scenes": [{"nodes": [0]}, {"nodes": [1]}],
        "nodes": [{"mesh": 0, "name": "Alternate"}, {"mesh": 0, "name": "Default"}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
        "accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [0, 0, 0], "max": [1, 1, 0]}],
        "bufferViews": [{"buffer": 0, "byteLength": len(vertices), "target": 34962}],
        "buffers": [{"byteLength": len(vertices), "uri": "data:application/octet-stream;base64," + base64.b64encode(vertices).decode()}]
    }
    gltf = root / "inputs/2.gltf"
    gltf.write_text(json.dumps(document))
    del document["buffers"][0]["uri"]
    payload = json.dumps(document).encode()
    payload += b" " * (-len(payload) % 4)
    glb = root / "inputs/3.glb"
    glb.write_bytes(struct.pack("<4sIII4s", b"glTF", 2, 28 + len(payload) + len(vertices), len(payload), b"JSON")
                    + payload + struct.pack("<I4s", len(vertices), b"BIN\x00") + vertices)
    for source in (gltf, glb):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        parent = worker.empty(bpy, "Render source")
        assert {obj.name for obj in worker.import_model(bpy, source, parent, {}) if obj.type == "MESH"} == {"Default"}

print("Verified render scene, collection visibility, starter exclusions, evaluated frame and GLB world positions.")
