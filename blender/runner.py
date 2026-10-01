import bpy
import json
import math
import os
import sys
import traceback
from mathutils import Vector


SCHEMA_VERSION = "1.0"


def log(message):
    print(f"[Studio Render] {message}", flush=True)


def parse_arguments():
    if "--" not in sys.argv:
        raise RuntimeError(
            "Studio manifest path and output directory were not supplied"
        )

    args = sys.argv[sys.argv.index("--") + 1:]

    if len(args) < 2:
        raise RuntimeError(
            "Expected: runner.py -- <manifest.json> <output_directory>"
        )

    return os.path.abspath(args[0]), os.path.abspath(args[1])


def load_manifest(path):
    if not os.path.isfile(path):
        raise RuntimeError(f"Manifest does not exist: {path}")

    with open(path, "r", encoding="utf-8") as handle:
        manifest = json.load(handle)

    version = str(manifest.get("schema_version", ""))

    if version != SCHEMA_VERSION:
        raise RuntimeError(
            f"Unsupported Studio manifest schema {version!r}; "
            f"expected {SCHEMA_VERSION!r}"
        )

    scene_data = manifest.get("scene")

    if not isinstance(scene_data, dict):
        raise RuntimeError("Manifest scene must be an object")

    return manifest


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    for datablocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.cameras,
        bpy.data.lights,
        bpy.data.materials,
    ):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def vector3(value, default):
    if not isinstance(value, (list, tuple)) or len(value) < 3:
        return list(default)

    return [
        float(value[0]),
        float(value[1]),
        float(value[2]),
    ]


def color3(value, default):
    result = vector3(value, default)

    return (
        max(0.0, min(1.0, result[0])),
        max(0.0, min(1.0, result[1])),
        max(0.0, min(1.0, result[2])),
    )


def color4(value, default):
    if not isinstance(value, (list, tuple)):
        value = default

    values = list(value) + list(default)

    return (
        float(values[0]),
        float(values[1]),
        float(values[2]),
        float(values[3]),
    )


def apply_transform(obj, definition):
    obj.location = vector3(
        definition.get("location"),
        [0.0, 0.0, 0.0],
    )

    obj.rotation_euler = vector3(
        definition.get("rotation"),
        [0.0, 0.0, 0.0],
    )

    if hasattr(obj, "scale"):
        obj.scale = vector3(
            definition.get("scale"),
            [1.0, 1.0, 1.0],
        )


def create_mesh(object_type, name, definition):
    if object_type == "cube":
        bpy.ops.mesh.primitive_cube_add()

    elif object_type == "sphere":
        bpy.ops.mesh.primitive_uv_sphere_add()

    elif object_type == "cylinder":
        bpy.ops.mesh.primitive_cylinder_add()

    elif object_type == "plane":
        bpy.ops.mesh.primitive_plane_add()

    else:
        raise RuntimeError(
            f"Unsupported Studio mesh object type: {object_type}"
        )

    obj = bpy.context.active_object
    obj.name = name
    apply_transform(obj, definition)

    material_definition = definition.get("material", {})

    if isinstance(material_definition, dict):
        rgba = color4(
            material_definition.get("color"),
            [0.55, 0.58, 0.65, 1.0],
        )

        material = bpy.data.materials.new(
            name=f"{name}_Material"
        )
        material.diffuse_color = rgba
        material.use_nodes = True

        bsdf = material.node_tree.nodes.get(
            "Principled BSDF"
        )

        if bsdf:
            bsdf.inputs["Base Color"].default_value = rgba

        obj.data.materials.append(material)

    return obj


def create_camera(name, definition):
    data = bpy.data.cameras.new(name=name)
    obj = bpy.data.objects.new(name, data)

    bpy.context.scene.collection.objects.link(obj)

    apply_transform(obj, definition)

    data.lens = float(definition.get("lens", 50.0))

    bpy.context.scene.camera = obj

    return obj


def create_light(object_type, name, definition):
    light_types = {
        "point_light": "POINT",
        "sun_light": "SUN",
        "area_light": "AREA",
    }

    data = bpy.data.lights.new(
        name=name,
        type=light_types[object_type],
    )

    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)

    apply_transform(obj, definition)

    data.energy = float(
        definition.get(
            "energy",
            3.0 if object_type == "sun_light" else 1000.0,
        )
    )

    data.color = color3(
        definition.get("color"),
        [1.0, 0.95, 0.9],
    )

    if object_type == "area_light":
        data.shape = "DISK"
        data.size = float(definition.get("size", 5.0))

    return obj


def create_manifest_object(item):
    object_type = str(item.get("type", "")).strip()
    name = str(
        item.get("name")
        or f"Studio_{object_type}"
    )

    definition = item.get("definition") or {}

    if not isinstance(definition, dict):
        raise RuntimeError(
            f"Definition for {name!r} must be an object"
        )

    if object_type in {
        "cube",
        "sphere",
        "cylinder",
        "plane",
    }:
        return create_mesh(
            object_type,
            name,
            definition,
        )

    if object_type == "camera":
        return create_camera(
            name,
            definition,
        )

    if object_type in {
        "point_light",
        "sun_light",
        "area_light",
    }:
        return create_light(
            object_type,
            name,
            definition,
        )

    raise RuntimeError(
        f"Unsupported Studio object type: {object_type!r}"
    )


def point_at(obj, target=(0.0, 0.0, 0.0)):
    direction = Vector(target) - obj.location

    if direction.length == 0:
        return

    obj.rotation_euler = direction.to_track_quat(
        "-Z",
        "Y",
    ).to_euler()


def ensure_camera():
    scene = bpy.context.scene

    if scene.camera:
        return scene.camera

    log("Manifest contains no camera; creating Studio default camera")

    camera = create_camera(
        "Studio_Default_Camera",
        {
            "location": [6.5, -8.0, 5.0],
            "lens": 50,
        },
    )

    point_at(camera, (0.0, 0.0, 0.5))

    return camera


def ensure_lighting():
    existing = [
        obj
        for obj in bpy.context.scene.objects
        if obj.type == "LIGHT"
    ]

    if existing:
        return

    log("Manifest contains no lights; creating Studio default lighting")

    key = create_light(
        "area_light",
        "Studio_Key_Light",
        {
            "location": [4.0, -4.0, 6.0],
            "energy": 1200,
            "size": 5.0,
            "color": [1.0, 0.82, 0.68],
        },
    )

    point_at(key, (0.0, 0.0, 0.0))

    fill = create_light(
        "area_light",
        "Studio_Fill_Light",
        {
            "location": [-4.0, -2.0, 3.0],
            "energy": 500,
            "size": 4.0,
            "color": [0.55, 0.7, 1.0],
        },
    )

    point_at(fill, (0.0, 0.0, 0.0))


def configure_world(settings):
    scene = bpy.context.scene

    world = scene.world

    if world is None:
        world = bpy.data.worlds.new("Studio_World")
        scene.world = world

    world.use_nodes = True

    background = world.node_tree.nodes.get("Background")

    if background:
        background.inputs["Color"].default_value = color4(
            settings.get("world_color"),
            [0.03, 0.03, 0.03, 1.0],
        )

        background.inputs["Strength"].default_value = float(
            settings.get("world_strength", 0.35)
        )


def configure_render(settings):
    scene = bpy.context.scene

    requested_engine = str(
        settings.get(
            "render_engine",
            "BLENDER_EEVEE_NEXT",
        )
    )

    engine_candidates = [requested_engine]

    if requested_engine == "BLENDER_EEVEE_NEXT":
        engine_candidates.append("BLENDER_EEVEE")

    configured = False

    for engine in engine_candidates:
        try:
            scene.render.engine = engine
            configured = True
            log(f"Render engine: {engine}")
            break
        except (TypeError, ValueError):
            continue

    if not configured:
        log(
            f"Requested render engine {requested_engine!r} "
            "is unavailable; using Blender default"
        )

    scene.render.resolution_x = int(
        settings.get("resolution_x", 1280)
    )

    scene.render.resolution_y = int(
        settings.get("resolution_y", 720)
    )

    scene.render.resolution_percentage = int(
        settings.get("resolution_percentage", 100)
    )

    scene.render.image_settings.file_format = "PNG"

    scene.render.film_transparent = bool(
        settings.get(
            "transparent_background",
            False,
        )
    )


def save_blend(path):
    log(f"Saving Studio scene: {path}")

    bpy.ops.wm.save_as_mainfile(
        filepath=path,
        check_existing=False,
    )


def export_glb(path):
    log(f"Exporting GLB: {path}")

    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=False,
    )


def render_preview(path):
    scene = bpy.context.scene

    scene.render.filepath = path

    log(f"Rendering preview: {path}")

    bpy.ops.render.render(write_still=True)


def requested_outputs(manifest):
    outputs = manifest.get("outputs") or {}

    if not isinstance(outputs, dict):
        raise RuntimeError("Manifest outputs must be an object")

    return outputs


def write_result(output_directory, payload):
    path = os.path.join(
        output_directory,
        "render_result.json",
    )

    with open(path, "w", encoding="utf-8") as handle:
        json.dump(
            payload,
            handle,
            indent=2,
            sort_keys=True,
        )


def main():
    manifest_path, output_directory = parse_arguments()

    os.makedirs(
        output_directory,
        exist_ok=True,
    )

    try:
        manifest = load_manifest(manifest_path)

        log(
            "Building Studio manifest "
            f"{manifest.get('schema_version')}"
        )

        clear_scene()

        scene_data = manifest["scene"]
        settings = scene_data.get("settings") or {}

        if not isinstance(settings, dict):
            raise RuntimeError(
                "Scene settings must be an object"
            )

        configure_world(settings)
        configure_render(settings)

        objects = scene_data.get("objects") or []

        if not isinstance(objects, list):
            raise RuntimeError(
                "Scene objects must be an array"
            )

        for item in objects:
            if not isinstance(item, dict):
                raise RuntimeError(
                    "Every scene object must be an object"
                )

            obj = create_manifest_object(item)

            log(
                f"Created {item.get('type')} "
                f"{obj.name!r}"
            )

        ensure_camera()
        ensure_lighting()

        outputs = requested_outputs(manifest)
        generated = []

        if outputs.get("blend"):
            path = os.path.join(
                output_directory,
                "scene.blend",
            )
            save_blend(path)
            generated.append("scene.blend")

        if outputs.get("glb"):
            path = os.path.join(
                output_directory,
                "scene.glb",
            )
            export_glb(path)
            generated.append("scene.glb")

        if outputs.get("preview"):
            path = os.path.join(
                output_directory,
                "preview.png",
            )
            render_preview(path)
            generated.append("preview.png")

        write_result(
            output_directory,
            {
                "status": "succeeded",
                "schema_version": SCHEMA_VERSION,
                "generated": generated,
            },
        )

        log(
            "Studio render completed: "
            + ", ".join(generated)
        )

    except Exception as error:
        write_result(
            output_directory,
            {
                "status": "failed",
                "error": str(error),
                "traceback": traceback.format_exc(),
            },
        )

        traceback.print_exc()
        raise


if __name__ == "__main__":
    main()
