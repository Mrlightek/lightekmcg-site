"""Import Blender-compatible 3D exports and write a self-contained GLB."""
import argparse
import json
from pathlib import Path
import struct
import sys
from urllib.parse import unquote, urlsplit

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))

from scene_renderer import JobError, check_glb, import_glb


def gltf_metadata(path):
    if path.suffix.lower() == ".gltf":
        return json.loads(path.read_text(encoding="utf-8-sig"))
    with path.open("rb") as stream:
        magic, version, total = struct.unpack("<4sII", stream.read(12))
        size, tag = struct.unpack("<I4s", stream.read(8))
        if (magic, version, tag) != (b"glTF", 2, b"JSON") or total != path.stat().st_size or size > total - 20:
            raise JobError(f"Invalid GLB 2.0 container: {path}")
        return json.loads(stream.read(size))


def validate_sidecars(path, metadata, bundle):
    for item in (*metadata.get("buffers", []), *metadata.get("images", [])):
        uri = item.get("uri")
        if uri is None or uri.startswith("data:"):
            continue
        if bundle is None:
            raise JobError(f"{path.name} references {uri!r}. Drop it in a folder with its sidecars.")
        url = urlsplit(uri)
        relative = Path(unquote(url.path))
        if url.scheme or url.netloc or url.query or url.fragment or relative.is_absolute() or "\\" in str(relative):
            raise JobError(f"Expected a relative local glTF sidecar URI, got {uri!r}")
        target = (path.parent / relative).resolve()
        if not target.is_relative_to(bundle) or not target.is_file():
            raise JobError(f"Missing sidecar or reference outside the bundle: {uri!r}")


def normalize(args):
    source = args.input.resolve(strict=True)
    output = args.out.absolute()
    if source == output.resolve() or output.suffix != ".glb":
        raise JobError("--out must be a different .glb file")
    if not 0.000001 <= args.scale_multiplier <= 1_000_000:
        raise JobError("Scale multiplier must be between 0.000001 and 1000000")
    bundle = args.bundle.resolve(strict=True) if args.bundle else None
    if bundle and not source.is_relative_to(bundle):
        raise JobError("The source must be inside the bundle")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.fps = 30
    scene.render.fps_base = 1
    scene.frame_start = 1
    source_suffix = source.suffix.lower()
    source_animations = 0
    if source_suffix == ".fbx":
        # Let Blender read FBX axis and unit metadata. Keep the bind matrices.
        result = bpy.ops.import_scene.fbx(filepath=str(source), global_scale=1.0,
                                         bake_space_transform=False, use_image_search=bundle is not None)
        animation_mode = "ACTIONS"
    elif source_suffix in {".glb", ".gltf"}:
        metadata = gltf_metadata(source)
        validate_sidecars(source, metadata, bundle)
        source_animations = len(metadata.get("animations", []))
        result, _ = import_glb(source)
        animation_mode = "NLA_TRACKS"
    else:
        raise JobError(f"Unsupported asset format: {source_suffix}")
    if "FINISHED" not in result or not any(obj.type == "MESH" for obj in scene.objects):
        raise JobError(f"Import did not produce a mesh: {source}")

    for image in bpy.data.images:
        if image.source == "FILE" and not image.packed_file:
            external = Path(bpy.path.abspath(image.filepath)).resolve()
            if not external.is_file():
                raise JobError(f"Missing texture: {image.filepath}")
            if bundle is None or not external.is_relative_to(bundle):
                raise JobError(f"External texture {image.filepath!r}. Drop the model and textures in one bundle.")

    # Correct bad source units uniformly at the asset root. Applying transforms
    # separately to the mesh and rig can break skinning and animated offsets.
    if args.scale_multiplier != 1.0:
        roots = [obj for obj in scene.objects if obj.parent is None]
        root = bpy.data.objects.new("Unit correction", None)
        scene.collection.objects.link(root)
        for obj in roots:
            obj.parent = root
        root.scale = (args.scale_multiplier,) * 3

    if args.mixamo_out:
        for obj in list(scene.objects):
            if obj.type in {"CAMERA", "LIGHT"}:
                bpy.data.objects.remove(obj, do_unlink=True)
        result = bpy.ops.export_scene.fbx(filepath=str(args.mixamo_out), bake_anim=False,
                                          add_leaf_bones=False, path_mode="COPY", embed_textures=True)
        if "FINISHED" not in result or not args.mixamo_out.is_file():
            raise JobError("Blender did not write the Mixamo FBX")
        return
    result = bpy.ops.export_scene.gltf(
        filepath=str(output), export_format="GLB", export_yup=True,
        export_apply=False, export_cameras=False, export_lights=False,
        export_animations=True, export_animation_mode=animation_mode,
        export_frame_range=False, export_force_sampling=True, export_anim_slide_to_zero=True,
        export_skins=True, export_all_influences=True, export_morph=True,
        export_morph_animation=True,
    )
    if "FINISHED" not in result or not output.is_file():
        raise JobError("Blender did not write the GLB")
    check_glb(output)
    clip_names = [clip.get("name", "<unnamed>") for clip in gltf_metadata(output).get("animations", [])]
    if len(clip_names) < source_animations:
        raise JobError(f"Export lost animation clips ({source_animations} in, {len(clip_names)} out)")
    if source_suffix == ".fbx" and len(bpy.data.actions) and not clip_names:
        raise JobError("FBX contains imported actions but none were exportable")
    if args.require_animation and not clip_names:
        raise JobError("The FBX does not contain an animation clip")
    print(f"Normalized {source.name} to {output.name}. Clips: {', '.join(clip_names) or 'none'}.", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--bundle", type=Path)
    parser.add_argument("--mixamo-out", type=Path)
    parser.add_argument("--require-animation", action="store_true")
    parser.add_argument("--scale-multiplier", type=float, default=1)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    try:
        normalize(args)
    except (JobError, OSError, ValueError, RuntimeError) as error:
        raise SystemExit(f"normalize: {error}") from error


if __name__ == "__main__":
    main()
