"""Build the Studio scene manifest in Blender, then mux its audio with FFmpeg."""

import json
import math
import re
import struct
import subprocess
import sys
from pathlib import Path
from xml.etree import ElementTree

INPUT = re.compile(r"inputs/[1-9][0-9]*\.(png|webp|svg|glb|gltf|fbx|blend|wav|mp3|m4a|aac|ogg|flac)\Z")
SVG_TAGS = {
    "svg", "g", "defs", "title", "desc", "use", "symbol", "path", "rect", "circle",
    "ellipse", "line", "polyline", "polygon", "linearGradient", "radialGradient",
    "stop", "clipPath", "mask",
}


def input_path(root, name):
    if not isinstance(name, str) or not INPUT.fullmatch(name):
        raise ValueError("Invalid render input path")
    path = (root / name).resolve(strict=True)
    if path.parent != root / "inputs":
        raise ValueError("Render input leaves the work directory")
    return path


def rasterize_svg(path):
    # Only local vector shapes and fragment references enter the rasterizer.
    # The media container also has no network access.
    data = re.sub(rb"^\s*<\?xml\s+[^?]*\?>", b"", path.read_bytes(), count=1, flags=re.I)
    if len(data) > 4 * 1024 * 1024 or b"\x00" in data or re.search(rb"<!DOCTYPE|<!ENTITY|<\?", data, re.I):
        raise ValueError("Unsupported SVG declaration or size")
    tree = ElementTree.fromstring(data)
    if tree.tag.rsplit("}", 1)[-1] != "svg":
        raise ValueError("Expected an SVG image")
    for node in tree.iter():
        if node.tag.rsplit("}", 1)[-1] not in SVG_TAGS:
            raise ValueError("Unsupported SVG element")
        for attr, value in node.attrib.items():
            name = attr.rsplit("}", 1)[-1].lower()
            safe_fragment = re.fullmatch(r"#[A-Za-z_][\w.:-]*", value)
            local_urls = re.sub(r"url\(\s*#[A-Za-z_][\w.:-]*\s*\)", "", value, flags=re.I)
            if name.startswith("on") or name == "base" or (name == "href" and not safe_fragment):
                raise ValueError("Unsupported SVG reference")
            if re.search(r"url\s*\(|@import|\\|/\*", local_urls, re.I):
                raise ValueError("Unsupported SVG style")
    output = path.with_suffix(".raster.png")
    if not output.exists():
        subprocess.run(
            ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
             "-f", "image2", "-c:v", "librsvg", "-width", "2048", "-height", "2048",
             "-i", str(path), "-frames:v", "1", "-threads", "2", "-pix_fmt", "rgba", str(output)],
            check=True,
            timeout=30,
        )
    return output


def frame_at(time_ms, fps):
    return 1 + time_ms * fps / 1000


def animate(object_, spec, fps):
    paths = {"position": "location", "rotation": "rotation_euler", "scale": "scale", "lens": "lens"}
    for field, path in paths.items():
        if field not in spec:
            continue
        target = object_.data if field == "lens" else object_
        keys = {0: (spec[field], "LINEAR")}
        keys.update({
            item["time_ms"]: (item[field], item.get("interpolation", "LINEAR"))
            for item in spec["keyframes"] if field in item
        })
        for time, (value, _) in keys.items():
            if field == "rotation":
                value = tuple(math.radians(angle) for angle in value)
            setattr(target, path, value)
            if len(keys) > 1:
                target.keyframe_insert(data_path=path, frame=frame_at(time, fps))
        if len(keys) < 2:
            continue

        interpolation = [curve for _, curve in keys.values()]
        for curve in target.animation_data.action.fcurves:
            if curve.data_path != path:
                continue
            points = list(curve.keyframe_points)
            for point in points:
                point.handle_left_type = point.handle_right_type = "FREE"
                point.handle_left = point.handle_right = point.co
            for index, (left, right) in enumerate(zip(points, points[1:])):
                left.interpolation = interpolation[index + 1]
                third = (right.co.x - left.co.x) / 3
                left.handle_right = (left.co.x + third, left.co.y)
                right.handle_left = (right.co.x - third, right.co.y)
            curve.update()


def empty(bpy, name, parent=None):
    result = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(result)
    result.parent = parent
    return result


def card(bpy, root, source, parent, relief=0):
    path = input_path(root, source)
    if path.suffix == ".svg":
        path = rasterize_svg(path)
    image = bpy.data.images.load(str(path), check_existing=True)
    width, height = image.size
    if not width or not height or max(width, height) > 8192:
        raise ValueError("Artwork must be at most 8192 pixels per side")
    half_x, half_y = width / max(width, height), height / max(width, height)
    mesh = bpy.data.meshes.new(path.stem)
    mesh.from_pydata([(-half_x, -half_y, 0), (half_x, -half_y, 0),
                      (half_x, half_y, 0), (-half_x, half_y, 0)], [], [(0, 1, 2, 3)])
    uv = mesh.uv_layers.new()
    for loop, coords in zip(uv.data, [(0, 0), (1, 0), (1, 1), (0, 1)]):
        loop.uv = coords
    obj = bpy.data.objects.new(path.stem, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = parent
    material = bpy.data.materials.new(path.stem)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    links = material.node_tree.links
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = image
    opacity = nodes.new("ShaderNodeMixShader")
    transparent = nodes.new("ShaderNodeBsdfTransparent")
    if relief:
        shader = nodes.new("ShaderNodeBsdfPrincipled")
        bump = nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = relief
        bump.inputs["Distance"].default_value = 0.1
        links.new(texture.outputs["Color"], bump.inputs["Height"])
        links.new(bump.outputs["Normal"], shader.inputs["Normal"])
        links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    else:
        shader = nodes.new("ShaderNodeEmission")
        links.new(texture.outputs["Color"], shader.inputs["Color"])
    links.new(texture.outputs["Alpha"], opacity.inputs[0])
    links.new(transparent.outputs[0], opacity.inputs[1])
    links.new(shader.outputs[0], opacity.inputs[2])
    links.new(opacity.outputs[0], nodes.new("ShaderNodeOutputMaterial").inputs["Surface"])
    mesh.materials.append(material)
    return obj


def cue_changes(cues, fps, frame_count, variants):
    changes = {1: "X"}
    for cue in cues:
        first = math.ceil(frame_at(cue["start_ms"], fps))
        after = math.ceil(frame_at(cue["end_ms"], fps))
        if first >= after or first > frame_count:
            continue
        changes[first] = cue["viseme"] if cue["viseme"] in variants else "X"
        if after <= frame_count:
            changes[after] = "X"
    return sorted(changes.items())


def mouth_cards(bpy, root, mouth, parent, fps, frame_count):
    changes = cue_changes(mouth["cues"], fps, frame_count, mouth["variants"])
    for shape, source in mouth["variants"].items():
        obj = card(bpy, root, source, parent)
        x, y, z = mouth["position"]
        obj.location = (x, y, z + 0.005)
        obj.scale = mouth["scale"]
        for frame, visible in changes:
            obj.hide_render = shape != visible
            obj.keyframe_insert(data_path="hide_render", frame=frame)


def check_gltf(path):
    def walk(item):
        if isinstance(item, dict):
            for key, value in item.items():
                if key == "uri" and (not isinstance(value, str) or
                                     not re.match(r"data:[\w.+/-]+;base64,", value)):
                    raise ValueError("Use a self-contained glTF with embedded buffers and textures")
                if key != "uri":
                    walk(value)
        elif isinstance(item, list):
            for value in item:
                walk(value)

    if path.suffix == ".gltf":
        document = json.loads(path.read_text(encoding="utf-8"))
    else:
        with path.open("rb") as file:
            header = file.read(20)
            if len(header) != 20 or header[:8] != b"glTF\x02\x00\x00\x00" or header[16:] != b"JSON":
                raise ValueError("Invalid glTF binary header")
            size = int.from_bytes(header[12:16], "little")
            if size > path.stat().st_size - 20:
                raise ValueError("Invalid glTF JSON size")
            document = json.loads(file.read(size))
    walk(document)
    return document


GLTF_EXCLUDED = "_lightek_outside_active_scene"


def studio_gltf_source(path):
    document = check_gltf(path)
    scenes = document.get("scenes", [])
    if not scenes:
        return path, False
    nodes = document.get("nodes", [])
    included = set()
    pending = list(scenes[document.get("scene", 0)].get("nodes", []))
    while pending:
        node = pending.pop()
        if node not in included:
            included.add(node)
            pending.extend(nodes[node].get("children", []))
    if len(included) == len(nodes):
        return path, False

    # Blender imports every glTF root. Tag the out-of-scene geometry in the
    # worker copy so that Studio renders the same scene as GLTFLoader.
    for index, node in enumerate(nodes):
        extras = node.get("extras")
        node["extras"] = {**(extras if isinstance(extras, dict) else {}), GLTF_EXCLUDED: index not in included}
    target = path.with_name(f"studio-scene-{path.name}")
    payload = json.dumps(document, separators=(",", ":")).encode()
    if path.suffix == ".gltf":
        target.write_bytes(payload)
    else:
        with path.open("rb") as file:
            file.seek(12)
            size = int.from_bytes(file.read(4), "little")
            file.seek(20 + size)
            remaining = file.read()
        payload += b" " * (-len(payload) % 4)
        header = struct.pack("<4sIII4s", b"glTF", 2, 20 + len(payload) + len(remaining), len(payload), b"JSON")
        target.write_bytes(header + payload + remaining)
    return target, True


MESH_TYPES = {"MESH", "CURVE", "SURFACE", "FONT", "META"}


def render_collection_objects(layer):
    if layer.exclude or layer.collection.hide_render:
        return set()
    objects = set(layer.collection.objects)
    for child in layer.children:
        objects.update(render_collection_objects(child))
    return objects


def model_excluded(obj, starter):
    return obj.type in {"CAMERA", "LIGHT"} or (starter and (
        obj.get("lightek_character_floor") or obj.name.split(".")[0] == "Studio floor"))


def link_model(bpy, parent, objects, visible, starter, *, native):
    scene = bpy.context.scene
    hidden = bpy.data.collections.new("Studio render exclusions")
    hidden.hide_render = True
    scene.collection.children.link(hidden)
    included = set()
    for obj in objects:
        if obj.parent not in objects:
            obj.parent = parent
        # The source's viewport switches are not render switches. Keep hidden
        # rig dependencies linked and evaluable without rendering them.
        obj.hide_viewport = False
        if obj in visible and not model_excluded(obj, starter):
            destination = scene.collection
            included.add(obj)
        else:
            destination = hidden
        if obj not in destination.objects.values():
            destination.objects.link(obj)
        if not native:
            for collection in list(obj.users_collection):
                if collection != destination:
                    collection.objects.unlink(obj)
        obj.hide_set(False)
    return included, hidden


def import_model(bpy, path, parent, layer):
    before = set(bpy.data.objects)
    previous_actions = set(bpy.data.actions)
    filtered_gltf = False
    if path.suffix in (".glb", ".gltf"):
        source, filtered_gltf = studio_gltf_source(path)
        bpy.ops.import_scene.gltf(filepath=str(source))
    elif path.suffix == ".fbx":
        bpy.ops.import_scene.fbx(filepath=str(path), use_image_search=False)
    elif path.suffix == ".blend":
        wanted = layer.get("action")
        with bpy.data.libraries.load(str(path), link=False) as (available, loaded):
            if not available.scenes:
                raise ValueError("The Blender file contains no scene")
            loaded.scenes = [min(available.scenes, key=lambda name: (name.casefold(), name))]
            if wanted:
                if wanted not in available.actions:
                    raise ValueError(f"Action {wanted!r} is missing")
                loaded.actions = [wanted]
        source = loaded.scenes[0]
        primary_layer = next((view for view in source.view_layers if view.use), None)
        objects = set(source.objects)
        visible = render_collection_objects(primary_layer.layer_collection) if primary_layer else set()
    else:
        raise ValueError("Unsupported model file")
    if path.suffix != ".blend":
        scene = bpy.context.scene
        objects = (set(bpy.data.objects) - before) & set(scene.objects)
        visible = render_collection_objects(bpy.context.view_layer.layer_collection) & objects
    imported = sorted(objects, key=lambda obj: obj.name)
    if filtered_gltf:
        visible = {obj for obj in visible if not obj.get(GLTF_EXCLUDED)}
    included, hidden = link_model(bpy, parent, objects, visible, layer.get("starter", False), native=path.suffix == ".blend")
    if not any(obj.type in MESH_TYPES or obj.is_instancer for obj in included):
        raise ValueError("The source scene has no render-visible meshes")
    if path.suffix in (".glb", ".gltf"):
        apply_gltf_animation(bpy, imported, previous_actions, layer.get("action"))
    elif layer.get("action"):
        armatures = [obj for obj in imported if obj.type == "ARMATURE"]
        action = loaded.actions[0] if path.suffix == ".blend" else next(
            (item for item in bpy.data.actions if item not in previous_actions and
             (item.name == layer["action"] or re.sub(r"\.[0-9]{3,}$", "", item.name) == layer["action"])),
            None,
        )
        if len(armatures) != 1 or not action:
            raise ValueError("A named action needs one armature and an action in the source model")
        animation = armatures[0].animation_data_create()
        for track in animation.nla_tracks:
            track.mute = True
        animation.action = action
        slots = [slot for slot in getattr(action, "slots", []) if slot.target_id_type == "OBJECT"]
        if slots and animation.action_slot is None:
            animation.action_slot = slots[0]
    if "pose_frame" in layer:
        return bake_pose(bpy, parent, included, hidden, layer["pose_frame"])
    return included


def apply_gltf_animation(bpy, objects, previous_actions, name):
    # glTF actions import on a zero-based clock. Studio evaluates frame 1
    # at time zero. Shift every imported channel, including shape keys.
    for action in set(bpy.data.actions) - previous_actions:
        bags = [bag for layer in getattr(action, "layers", []) for strip in layer.strips
                for bag in getattr(strip, "channelbags", [])]
        for curves in [bag.fcurves for bag in bags] or [action.fcurves]:
            for curve in curves:
                for point in curve.keyframe_points:
                    point.co.x += 1
                    point.handle_left.x += 1
                    point.handle_right.x += 1
                curve.update()
    if not name:
        return
    matched = False
    for obj in objects:
        for animated in (obj, getattr(obj.data, "shape_keys", None)):
            data = getattr(animated, "animation_data", None)
            if not data:
                continue
            strip = next((track.strips[0] for track in data.nla_tracks if track.name == name and track.strips), None)
            for track in data.nla_tracks:
                track.mute = True
            data.action = strip.action if strip else None
            if strip and getattr(strip, "action_slot", None):
                data.action_slot = strip.action_slot
            matched = matched or bool(strip)
    if not matched:
        raise ValueError(f"Action {name!r} is missing from the glTF model")


def bake_pose(bpy, parent, included, hidden, frame):
    scene = bpy.context.scene
    scene.frame_set(frame)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    relative = parent.matrix_world.inverted_safe()
    baked = []
    # Read the dependency graph before linking any copies, since a scene
    # mutation can invalidate the object-instance iterator.
    for instance in depsgraph.object_instances:
        evaluated = instance.object
        owner = instance.parent if instance.is_instance else evaluated
        if not owner or owner.original not in included or owner.hide_render or evaluated.hide_render:
            continue
        if evaluated.type not in MESH_TYPES:
            continue
        mesh = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True, depsgraph=depsgraph)
        copy = bpy.data.objects.new(f"{evaluated.original.name} · pose", mesh)
        baked.append((copy, relative @ instance.matrix_world))
    for copy, matrix in baked:
        scene.collection.objects.link(copy)
        copy.parent = parent
        copy.matrix_basis = matrix
    # Retain dependencies but remove original geometry from the render view.
    for obj in included:
        hidden.objects.link(obj)
        scene.collection.objects.unlink(obj)
    scene.frame_set(1)
    return [copy for copy, _ in baked]


def position_with_depth(layer):
    offset = layer.get("z_depth", 0) - layer["z_layer"] * 0.015

    def shift(position):
        return [position[0], position[1] + offset, position[2]]

    keys = [
        {**key, "position": shift(key["position"])} if "position" in key else key
        for key in layer["keyframes"]
    ]
    return {**layer, "position": shift(layer["position"]), "keyframes": keys}


def build(bpy, spec, root):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    fps = spec["fps"]
    scene.frame_start = 1
    scene.frame_end = spec["frame_count"]
    scene.render.fps = fps
    camera = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera.data.sensor_fit = "VERTICAL" if spec["aspect_ratio"] == "9:16" else "HORIZONTAL"
    camera.data.sensor_width = camera.data.sensor_height = 36
    animate(camera, spec["camera"], fps)

    # X is horizontal, Z is vertical and positive Y recedes from the camera.
    for number, layer in enumerate(spec["layers"], 1):
        placement = empty(bpy, f"Layer {number}")
        adjusted = position_with_depth(layer)
        if layer["dimension_mode"] == "3d":
            import_model(bpy, input_path(root, layer["source"]), placement, layer)
            animate(placement, adjusted, fps)
            continue
        # The billboard follows camera rotation. Authored rotation and scale
        # remain local to the artwork and its mouth overlay.
        facing = empty(bpy, f"Card {number}", placement)
        follow = facing.constraints.new("COPY_ROTATION")
        follow.target = camera
        artwork = empty(bpy, f"Artwork {number}", facing)
        card(bpy, root, layer["source"], artwork, layer.get("relief", 0))
        if "mouth" in layer:
            mouth_cards(bpy, root, layer["mouth"], artwork, fps, scene.frame_end)
        animate(placement, {"position": adjusted["position"], "keyframes": adjusted["keyframes"]}, fps)
        animate(artwork, {key: layer[key] for key in ("rotation", "scale")} | {"keyframes": layer["keyframes"]}, fps)

    scene.world = bpy.data.worlds.new("Studio world")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.1, 0.1, 0.1, 1)
    scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.45
    light = bpy.data.lights.new("Key light", "AREA")
    light.energy, light.shape, light.size = 750, "DISK", 5
    lamp = bpy.data.objects.new("Key light", light)
    scene.collection.objects.link(lamp)
    lamp.location, lamp.rotation_euler = (0, -4, 4), (math.radians(55), 0, 0)
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 8
    scene.cycles.use_denoising = False
    scene.render.use_persistent_data = True
    scene.render.use_simplify = True
    scene.render.simplify_subdivision_render = 1
    scene.cycles.texture_limit_render = "2048"
    scene.render.threads_mode = "FIXED"
    scene.render.threads = 2
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x = spec["width"]
    scene.render.resolution_y = spec["height"]
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "FFMPEG"
    scene.render.ffmpeg.format = "MPEG4"
    scene.render.ffmpeg.codec = "H264"
    scene.render.ffmpeg.audio_codec = "NONE"
    scene.render.ffmpeg.constant_rate_factor = "MEDIUM"
    scene.render.filepath = str(root / "picture-")
    scene.frame_set(1)

    def progress(render_scene, *_args):
        temporary = root / "progress.tmp"
        temporary.write_text(str(render_scene.frame_current), encoding="ascii")
        temporary.replace(root / "progress")

    bpy.app.handlers.render_write.append(progress)
    bpy.ops.render.render(animation=True)


def encode(root, spec):
    pictures = list(root.glob("picture-*.mp4"))
    if len(pictures) != 1:
        raise RuntimeError("Blender video output is missing")
    if spec["audio"]:
        path = input_path(root, spec["audio"])
        demuxer = {".wav": "wav", ".mp3": "mp3", ".m4a": "mov", ".aac": "aac",
                   ".ogg": "ogg", ".flac": "flac"}[path.suffix]
        audio = ["-protocol_whitelist", "file,pipe", "-f", demuxer, "-threads", "2", "-i", str(path)]
    else:
        audio = ["-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000"]
    duration = spec["frame_count"] / spec["fps"]
    subprocess.run(
        ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
         "-i", str(pictures[0]), *audio, "-map", "0:v:0", "-map", "1:a:0",
         "-c:v", "copy", "-af", "apad", "-c:a", "aac", "-ar", "48000", "-ac", "2",
         "-t", f"{duration:.6f}", "-movflags", "+faststart", str(root / "scene.mp4")],
        check=True,
        timeout=105,
    )


def preview(bpy, spec, root):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = spec["fps"]
    parent = empty(bpy, "Model")
    layer = {**spec, "pose_frame": spec.get("pose_frame", 1)}
    baked = import_model(bpy, input_path(root, spec["source"]), parent, layer)
    if not baked:
        raise ValueError("No render-visible meshes at the requested frame")
    bpy.ops.object.select_all(action="DESELECT")
    parent.select_set(True)
    for obj in baked:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(root / "preview.glb"), export_format="GLB",
                              export_yup=True, use_selection=True, export_animations=False,
                              export_cameras=False, export_lights=False)


def main(args):
    phase, manifest = args
    path = Path(manifest).resolve()
    spec = json.loads(path.read_text(encoding="utf-8"))
    if spec["version"] != 1:
        raise ValueError("Unsupported scene manifest version")
    if phase == "render":
        import bpy
        build(bpy, spec, path.parent)
    elif phase == "preview":
        import bpy
        preview(bpy, spec, path.parent)
    elif phase == "encode":
        encode(path.parent, spec)
    else:
        raise ValueError("Unknown render phase")


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
