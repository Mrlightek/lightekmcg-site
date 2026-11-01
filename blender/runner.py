import bpy
import json
import math
import os
import sys
import traceback
import zipfile
from mathutils import Vector, Matrix, Euler


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

    obj.rotation_euler = [math.radians(value) for value in vector3(
        definition.get("rotation"),
        [0.0, 0.0, 0.0],
    )]

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
            for field, socket in (("metallic", "Metallic"), ("roughness", "Roughness"), ("transmission", "Transmission Weight")):
                value = material_definition.get(field)
                if isinstance(value, (int, float)) and math.isfinite(value) and socket in bsdf.inputs:
                    bsdf.inputs[socket].default_value = max(0.0, min(1.0, value))
            if "Alpha" in bsdf.inputs:
                bsdf.inputs["Alpha"].default_value = rgba[3]
            if rgba[3] < 1 and hasattr(material, "surface_render_method"):
                material.surface_render_method = "DITHERED"
            elif rgba[3] < 1 and hasattr(material, "blend_method"):
                material.blend_method = "BLEND"

        obj.data.materials.append(material)

    return obj


def clear_camera_animation(data, path):
    animation = data.animation_data
    if not animation:
        return
    if animation.action:
        animation.action = animation.action.copy()
        for curve in list(getattr(animation.action, 'fcurves', [])):
            if curve.data_path == path:
                animation.action.fcurves.remove(curve)
    for curve in list(animation.drivers):
        if curve.data_path == path:
            data.driver_remove(path)


def configure_camera(obj, definition, native=False):
    data = obj.data
    original = definition.get("native_original") if native else None
    changed = lambda key: original is None or definition.get(key) != original.get(key)
    if native and original and data.users > 1 and any(changed(key) for key in definition if key not in {'native_original','location','rotation','scale','blender_object_name'}):
        obj.data = data.copy()
        data = obj.data
    transform_changed = any(changed(key) for key in ("location", "rotation", "scale"))
    if native and transform_changed:
        obj.matrix_world = Matrix.LocRotScale(Vector(vector3(definition.get("location"), [0,0,0])),
            Euler([math.radians(v) for v in vector3(definition.get("rotation"), [0,0,0])]).to_quaternion(),
            Vector(vector3(definition.get("scale"), [1,1,1])))
    elif not native:
        apply_transform(obj, definition)
    fields = {"camera_type":"type", "lens":"lens", "lens_unit":"lens_unit", "sensor_fit":"sensor_fit", "sensor_width":"sensor_width", "sensor_height":"sensor_height",
        "shift_x":"shift_x", "shift_y":"shift_y", "clip_start":"clip_start", "clip_end":"clip_end", "ortho_scale":"ortho_scale"}
    for field, attribute in fields.items():
        if field in definition and changed(field):
            if native:
                clear_camera_animation(data, attribute)
            setattr(data, attribute, definition[field])
    if definition.get("lens_unit") == "FOV" and (changed("fov_degrees") or changed("lens_unit")):
        if native:
            clear_camera_animation(data, 'lens')
        data.angle = math.radians(float(definition.get("fov_degrees", 39.5978)))
    panorama = getattr(data, 'cycles', data)
    for field in ("panorama_type", "fisheye_lens", "fisheye_fov", "latitude_min", "latitude_max", "longitude_min", "longitude_max", "fisheye_polynomial_k0", "fisheye_polynomial_k1", "fisheye_polynomial_k2", "fisheye_polynomial_k3", "fisheye_polynomial_k4"):
        if field in definition and changed(field) and hasattr(panorama, field):
            setattr(panorama, field, math.radians(definition[field]) if field in {"fisheye_fov","latitude_min","latitude_max","longitude_min","longitude_max"} else definition[field])
    for field in ("convergence_mode", "pivot", "interocular_distance", "convergence_distance"):
        key = 'stereo_' + field
        if key in definition and changed(key):
            setattr(data.stereo, field, definition[key])
    dof = {"dof_enabled":"use_dof", "focus_distance":"focus_distance", "aperture_fstop":"aperture_fstop", "aperture_blades":"aperture_blades", "aperture_ratio":"aperture_ratio"}
    for field, attribute in dof.items():
        if field in definition and changed(field):
            if native:
                clear_camera_animation(data, 'dof.' + attribute)
            setattr(data.dof, attribute, definition[field])
    if "aperture_rotation" in definition and changed("aperture_rotation"):
        data.dof.aperture_rotation = math.radians(definition["aperture_rotation"])
    if "focus_object_name" in definition and changed("focus_object_name"):
        name = definition["focus_object_name"]
        target = bpy.context.scene.objects.get(name) if name else None
        if name and target is None:
            raise RuntimeError('The selected Blender focus object is unavailable')
        data.dof.focus_object = target


def configure_native_object(obj, definition):
    original = definition.get('native_original', {})
    changed = lambda key: definition.get(key) != original.get(key)
    if definition.get('native_deleted'):
        obj.hide_render = True
        obj.hide_viewport = True
        return
    for key, path in [('location', 'location'), ('rotation', 'rotation_euler'), ('scale', 'scale')]:
        if changed(key):
            clear_camera_animation(obj, path)
    if any(changed(key) for key in ('location', 'rotation', 'scale')):
        obj.matrix_world = Matrix.LocRotScale(Vector(definition['location']),
            Euler([math.radians(v) for v in definition['rotation']]).to_quaternion(), Vector(definition['scale']))
    for key in ('hide_render', 'hide_viewport'):
        if key in definition and changed(key):
            clear_camera_animation(obj, key)
            setattr(obj, key, bool(definition[key]))
    if obj.type == 'LIGHT':
        fields = [key for key in ('energy', 'size', 'color') if key in definition and changed(key)]
        if fields:
            obj.data = obj.data.copy()
            for key in fields:
                if hasattr(obj.data, key):
                    clear_camera_animation(obj.data, key)
                    setattr(obj.data, key, definition[key])
    override = definition.get('material_override')
    if override and len(obj.material_slots):
        obj.data = obj.data.copy()
        slot = definition.get('materials', [{}])[0].get('slot', 0)
        material = obj.material_slots[slot].material.copy()
        obj.data.materials[slot] = material
        material.use_nodes = True
        bsdf = material.node_tree.nodes.get('Principled BSDF')
        if bsdf:
            for key, socket in [('color', 'Base Color'), ('metallic', 'Metallic'), ('roughness', 'Roughness')]:
                if key in override:
                    for link in list(bsdf.inputs[socket].links):
                        material.node_tree.links.remove(link)
                    clear_camera_animation(material.node_tree, bsdf.inputs[socket].path_from_id("default_value"))
                    bsdf.inputs[socket].default_value = override[key]
    original_inputs = {(item['modifier'], item['identifier']): item['value'] for item in original.get('node_inputs', [])}
    for item in definition.get('node_inputs', []):
        if original_inputs.get((item['modifier'], item['identifier'])) == item['value']:
            continue
        mod = obj.modifiers.get(item['modifier'])
        if mod is None or mod.type != 'NODES' or mod.node_group is None:
            raise RuntimeError('The native Geometry Nodes modifier is unavailable')
        clear_camera_animation(obj, 'modifiers[' + json.dumps(mod.name) + '][' + json.dumps(item['identifier']) + ']')
        mod[item['identifier']] = item['value']
        obj.update_tag()


def create_camera(name, definition):
    data = bpy.data.cameras.new(name=name)
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    configure_camera(obj, definition)
    if not bpy.context.scene.camera:
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

    if object_type == "imported_asset":
        path = definition.get("asset_path")
        if not path or not os.path.isfile(path):
            raise RuntimeError("Imported asset proxy is unavailable")
        existing = set(bpy.context.scene.objects)
        if definition.get("asset_format") == "blend":
            with bpy.data.libraries.load(path, link=False) as (available, target):
                requested = definition.get("asset_scene")
                target.scenes = [requested] if requested in available.scenes else available.scenes[:1]
            source_scene = target.scenes[0]
            for collection in source_scene.collection.children:
                bpy.context.scene.collection.children.link(collection)
            for child in source_scene.collection.objects:
                bpy.context.scene.collection.objects.link(child)
        else:
            bpy.ops.import_scene.gltf(filepath=path)
        imported = set(bpy.context.scene.objects) - existing
        root = bpy.data.objects.new(name, None)
        bpy.context.scene.collection.objects.link(root)
        for child in imported:
            if child.parent not in imported:
                child.parent = root
        apply_transform(root, definition)
        return root

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


def apply_library_motion(obj, definition):
    target = definition.get("look_at")
    if isinstance(target, list) and len(target) == 3:
        point_at(obj, tuple(float(value) for value in target))
    animation = definition.get("animation") or {}
    frames = animation.get("frames", [])
    if not isinstance(frames, list) or len(frames) > 100:
        raise RuntimeError("Invalid library animation")
    fps = int(animation.get("fps", 24))
    if frames:
        bpy.context.scene.render.fps = max(1, min(60, fps))
    for frame in frames:
        number = int(frame["frame"])
        if not 1 <= number <= 14400:
            raise RuntimeError("Library frame is outside the supported range")
        bpy.context.scene.frame_end = max(bpy.context.scene.frame_end, number)
        if "location" in frame:
            obj.location = vector3(frame["location"], obj.location)
            obj.keyframe_insert(data_path="location", frame=number)
        if "rotation" in frame:
            obj.rotation_euler = [math.radians(value) for value in vector3(frame["rotation"], [0, 0, 0])]
            obj.keyframe_insert(data_path="rotation_euler", frame=number)
    # Linear interpolation matches the Studio viewport preview.
    if obj.animation_data and obj.animation_data.action:
        try:
            curves = obj.animation_data.action.fcurves
            for curve in curves:
                for point in curve.keyframe_points:
                    point.interpolation = "LINEAR"
        except AttributeError:
            pass


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

    if scene.render.engine == "CYCLES":
        scene.cycles.device = "CPU"
        scene.cycles.samples = max(1, min(256, int(settings.get("samples", 32))))
        scene.cycles.use_denoising = False

    scene.render.resolution_x = int(
        settings.get("resolution_x", 1280)
    )

    scene.render.resolution_y = int(
        settings.get("resolution_y", 720)
    )

    scene.render.resolution_percentage = int(
        settings.get("resolution_percentage", 100)
    )

    for field in ("frame_start", "frame_end"):
        if field in settings:
            setattr(scene, field, int(settings[field]))
    if "fps" in settings:
        scene.render.fps = int(settings["fps"])
    if "fps_base" in settings:
        scene.render.fps_base = float(settings["fps_base"])
    scene.frame_set(int(settings.get("frame_current", 1)))
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
    scene.render.image_settings.file_format = "PNG"

    log(f"Rendering preview: {path}")

    bpy.ops.render.render(write_still=True)


def export_project_bundle(output_directory, manifest):
    path = os.path.join(output_directory, 'project.zip')
    with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        archive.write(os.path.join(output_directory, 'scene.blend'), 'scene.blend')
        folder = os.path.join(output_directory, 'native-bundle')
        if os.path.isdir(folder):
            for directory, _children, files in os.walk(folder):
                for name in files:
                    source = os.path.join(directory, name)
                    archive.write(source, os.path.relpath(source, output_directory))
        archive.writestr('source-credits.json', json.dumps(manifest.get('credits', []), ensure_ascii=False, indent=2))


def apply_json_presets(settings, created):
    scene = bpy.context.scene
    for preset in settings.get('blender_presets', []):
        token = str(preset['instance'])
        prefix = 'LightekPreset_' + token
        # Preserve the complete historical definition alongside native outputs.
        text = bpy.data.texts.new(prefix + '.json')
        text.write(json.dumps(preset, ensure_ascii=False, indent=2))
        for marker in preset.get('markers', []):
            scene.timeline_markers.new(str(marker['name']), frame=int(marker['frame']))
        for index, item in enumerate(preset.get('texts', [])):
            curve = bpy.data.curves.new(prefix + '_Text', 'FONT')
            curve.body = str(item['body'])[:200]
            curve.align_x = 'CENTER'
            curve.size = 0.3
            obj = bpy.data.objects.new(prefix + '_Title', curve)
            scene.collection.objects.link(obj)
            camera = scene.camera
            frame = camera.data.view_frame(scene=scene)
            depth = 2.0
            factor = depth / abs(frame[0].z) if camera.data.type != 'ORTHO' else 1.0
            width = (max(v.x for v in frame) - min(v.x for v in frame)) * factor
            height = (max(v.y for v in frame) - min(v.y for v in frame)) * factor
            obj.parent = camera
            obj.location = (-width * 0.45, -height * 0.4 + index * height * 0.08, -depth)
            curve.align_x = 'LEFT'
            curve.size = width * 0.035
            material = bpy.data.materials.new(prefix + '_TitleColor')
            material.use_nodes = True
            shader = material.node_tree.nodes.get('Principled BSDF')
            shader.inputs['Base Color'].default_value = item['color']
            shader.inputs['Emission Color'].default_value = item['color']
            shader.inputs['Emission Strength'].default_value = 1
            curve.materials.append(material)
        for item in preset.get('materials', []):
            material = bpy.data.materials.new(str(item['name']))
            material.use_nodes = True
            bsdf = material.node_tree.nodes.get('Principled BSDF')
            bsdf.inputs['Base Color'].default_value = item['color']
            bsdf.inputs['Metallic'].default_value = float(item['metallic'])
            bsdf.inputs['Roughness'].default_value = float(item['roughness'])
            material.use_fake_user = True
        for item in preset.get('geometry_groups', []):
            parameters = item.get('parameters', {})
            group = bpy.data.node_groups.new(str(item['name']), 'GeometryNodeTree')
            group.interface.new_socket(name='Geometry', in_out='OUTPUT', socket_type='NodeSocketGeometry')
            inputs = group.nodes.new('NodeGroupInput')
            output = group.nodes.new('NodeGroupOutput')
            cube = group.nodes.new('GeometryNodeMeshCube')
            size = group.nodes.new('ShaderNodeCombineXYZ')
            size.inputs['X'].default_value = 4
            size.inputs['Y'].default_value = 2
            size.inputs['Z'].default_value = 0.3
            for name, value in parameters.items():
                socket = group.interface.new_socket(name=str(name), in_out='INPUT', socket_type='NodeSocketFloat')
                socket.default_value = float(value)
                if name in ('desk_length', 'bar_width', 'platform_radius'):
                    group.links.new(inputs.outputs[name], size.inputs['X'])
            group.links.new(size.outputs[0], cube.inputs['Size'])
            group.links.new(cube.outputs['Mesh'], output.inputs['Geometry'])
            mesh = bpy.data.meshes.new(prefix + '_Geometry')
            obj = bpy.data.objects.new(str(item.get('target_object', prefix)), mesh)
            scene.collection.objects.link(obj)
            modifier = obj.modifiers.new('JSON Geometry Preset', 'NODES')
            modifier.node_group = group
            obj['lightek_parameters'] = json.dumps(parameters)
        nodes = preset.get('nodes', [])
        if nodes:
            scene.use_nodes = True
            tree = scene.node_tree
            composite = next((n for n in tree.nodes if n.type == 'COMPOSITE'), None) or tree.nodes.new('CompositorNodeComposite')
            prior = composite.inputs['Image'].links[0].from_socket if composite.inputs['Image'].is_linked else None
            if prior is None:
                layer = tree.nodes.new('CompositorNodeRLayers')
                prior = layer.outputs['Image']
            types = {'glare': 'CompositorNodeGlare', 'colorbalance': 'CompositorNodeColorBalance',
                     'lensdistortion': 'CompositorNodeLensdist', 'chromaticaberration': 'CompositorNodeLensdist',
                     'rgbsplit': 'CompositorNodeLensdist', 'blur': 'CompositorNodeBlur'}
            for name in nodes:
                kind = types.get(str(name).lower().replace('_', ''))
                if not kind:
                    continue
                node = tree.nodes.new(kind)
                node.label = prefix + ': ' + name
                if kind == 'CompositorNodeGlare':
                    node.glare_type = 'FOG_GLOW'
                if kind == 'CompositorNodeLensdist':
                    node.inputs['Dispersion'].default_value = 0.015
                if kind == 'CompositorNodeBlur':
                    node.size_x = node.size_y = 2
                tree.links.new(prior, node.inputs['Image'])
                prior = node.outputs['Image']
            tree.links.new(prior, composite.inputs['Image'])


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


def stage_manifest(manifest):
    scene_data = manifest["scene"]
    settings = scene_data.get("settings") or {}
    if not isinstance(settings, dict):
        raise RuntimeError("Scene settings must be an object")
    native_path = manifest.get("native_template_path")
    if native_path:
        bpy.ops.wm.open_mainfile(filepath=native_path, load_ui=False, use_scripts=False)
        name = settings.get("native_scene")
        if name not in bpy.data.scenes:
            raise RuntimeError('Native Blender scene is unavailable')
        bpy.context.window.scene = bpy.data.scenes[name]
        scene = bpy.context.scene
        for field in ("resolution_x", "resolution_y", "resolution_percentage", "fps", "fps_base"):
            if field in settings:
                setattr(scene.render, field, settings[field])
        if "render_engine" in settings:
            scene.render.engine = settings["render_engine"]
        if "transparent_background" in settings:
            scene.render.film_transparent = bool(settings["transparent_background"])
        if scene.render.engine == "CYCLES":
            scene.cycles.device = 'CPU'
            if "samples" in settings:
                scene.cycles.samples = max(1, min(256, int(settings["samples"])))
        for field in ("frame_start", "frame_end"):
            if field in settings:
                setattr(scene, field, int(settings[field]))
        scene.frame_set(int(settings.get("frame_current", scene.frame_current)))
    else:
        clear_scene()
        configure_world(settings)
        configure_render(settings)

    objects = scene_data.get("objects") or []

    if not isinstance(objects, list):
        raise RuntimeError(
            "Scene objects must be an array"
        )

    created = {}
    for item in objects:
        if not isinstance(item, dict):
            raise RuntimeError(
                "Every scene object must be an object"
            )

        definition = item.get("definition") or {}
        if definition.get("native_source_preview"):
            continue
        if native_path and definition.get("native_duplicate_of"):
            original = bpy.context.scene.objects.get(definition["native_duplicate_of"])
            if original is None:
                raise RuntimeError("The source object for this Blender duplicate is unavailable")
            clone = original.copy()
            clone.data = original.data.copy() if original.data else None
            clone.name = definition["blender_object_name"]
            bpy.context.scene.collection.objects.link(clone)
        if native_path and item.get("type") == "native_object":
            obj = bpy.context.scene.objects.get(definition["blender_object_name"])
            if obj is None:
                raise RuntimeError("The native Blender object is unavailable")
            configure_native_object(obj, definition)
        elif native_path and item.get("type") == "camera" and definition.get("blender_object_name"):
            obj = bpy.context.scene.objects.get(definition["blender_object_name"])
            if obj is None or obj.type != 'CAMERA':
                raise RuntimeError('Native Blender camera is unavailable')
            configure_camera(obj, definition, native=True)
            configure_native_object(obj, definition)
        else:
            obj = create_manifest_object(item)
            apply_library_motion(obj, definition)
        if definition.get('staging_anchors'):
            for anchor_kind in ('rig', 'collision'):
                anchor=bpy.data.objects.new(obj.name+' '+anchor_kind+' anchor',None)
                bpy.context.scene.collection.objects.link(anchor);anchor.parent=obj;anchor['lightek_anchor_kind']=anchor_kind
        created[str(item.get("id"))] = obj

        log(
            f"Created {item.get('type')} "
            f"{obj.name!r}"
        )

    # An explicit production format takes precedence over recipe animation FPS.
    if "fps" in settings:
        bpy.context.scene.render.fps = int(settings["fps"])
    if "fps_base" in settings:
        bpy.context.scene.render.fps_base = float(settings["fps_base"])
    active_id = settings.get("active_camera_object_id")
    selected = created.get(str(active_id)) if active_id is not None else None
    if selected is None and settings.get("active_camera"):
        selected = bpy.context.scene.objects.get(settings["active_camera"])
    if selected is not None:
        if selected.type != 'CAMERA':
            raise RuntimeError('The active render camera must be a Blender camera')
        bpy.context.scene.camera = selected
    if bpy.context.scene.camera and any(item.get('definition', {}).get('native_deleted') and created.get(str(item.get('id'))) == bpy.context.scene.camera for item in objects):
        bpy.context.scene.camera = None
    ensure_camera()
    apply_json_presets(settings, created)
    if bpy.context.scene.camera.data.type == 'PANO':
        bpy.context.scene.render.engine = 'CYCLES'
    if not native_path:
        ensure_lighting()
        bpy.context.scene.frame_set(int(settings.get("frame_current", 1)))

    # Source identities stay stable while editing; resolve all references
    # first, then give native objects their saved display names.
    for item in objects:
        obj = created.get(str(item.get('id')))
        if obj is not None and item.get('definition', {}).get('native_original') and item.get('name'):
            obj.name = item['name']

    return created


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

        stage_manifest(manifest)

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

        if outputs.get("bundle"):
            export_project_bundle(output_directory, manifest)
            generated.append("project.zip")

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
