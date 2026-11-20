#!/usr/bin/env python3
"""Assemble a JSON scene and render it with Blender 4.3 or newer.

Run one job per Blender process. Manifest coordinates use Blender world axes
(Z up, meters). GLB files use glTF axes and are converted by Blender on import.
"""

import argparse
import json
import logging
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector


sys.path.insert(0, str(Path(__file__).resolve().parent))

from scene_renderer import (
    ENGINES, LIGHTING, LOG, MAX_FRAMES, JobError, build_camera, build_lighting,
    check_glb, configure_scene, enable_cycles_gpu, import_asset, integer, number,
    render_movie, require,
)

MIN_BLENDER = (4, 3, 0)


def unique_fields(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise JobError(f"Duplicate JSON field {key!r}")
        result[key] = value
    return result


def invalid_constant(value):
    raise JobError(f"Invalid JSON number {value!r}")


def fields(value, path, *names):
    require(isinstance(value, dict), path, "expected an object")
    missing = set(names) - value.keys()
    extra = value.keys() - set(names)
    require(not missing, path, f"missing fields {', '.join(sorted(missing))}")
    require(not extra, path, f"unknown fields {', '.join(sorted(extra))}")


def nonblank(value, field):
    require(isinstance(value, str) and value.strip(), field, "expected a nonblank string")


def vector(value, field):
    require(isinstance(value, list) and len(value) == 3, field, "expected three coordinates")
    for index, coordinate in enumerate(value):
        number(coordinate, f"{field}[{index}]")


def read_manifest(path):
    try:
        with path.open(encoding="utf-8") as source:
            manifest = json.load(source, object_pairs_hook=unique_fields,
                                 parse_constant=invalid_constant)
    except (OSError, ValueError) as error:
        raise JobError(f"Cannot read manifest {path}: {error}") from error

    fields(manifest, "manifest", "sceneId", "renderEngine", "resolution", "fps",
           "durationSeconds", "lightingPreset", "camera", "objects")
    nonblank(manifest["sceneId"], "sceneId")
    engine = manifest["renderEngine"]
    require(isinstance(engine, str) and engine in ENGINES, "renderEngine",
            "expected EEVEE or CYCLES")
    preset = manifest["lightingPreset"]
    require(isinstance(preset, str) and preset in LIGHTING, "lightingPreset",
            f"expected one of {', '.join(sorted(LIGHTING))}")

    size = manifest["resolution"]
    require(isinstance(size, list) and len(size) == 2, "resolution", "expected [width, height]")
    for index, dimension in enumerate(size):
        field = f"resolution[{index}]"
        size[index] = integer(dimension, field, 4, 65_536)
        require(size[index] % 2 == 0, field, "must be even for H.264")
    manifest["fps"] = integer(manifest["fps"], "fps", 1, 32_767)
    duration = manifest["durationSeconds"]
    number(duration, "durationSeconds")
    require(duration > 0, "durationSeconds", "must be positive")
    frame_count = math.floor(duration * manifest["fps"] + 0.5)
    require(1 <= frame_count <= MAX_FRAMES, "durationSeconds",
            f"must produce between 1 and {MAX_FRAMES} frames at the requested fps")

    camera = manifest["camera"]
    fields(camera, "camera", "position", "target", "fov")
    vector(camera["position"], "camera.position")
    vector(camera["target"], "camera.target")
    require(Vector(camera["position"]) != Vector(camera["target"]), "camera.target",
            "must differ from the camera position")
    number(camera["fov"], "camera.fov")
    require(1 <= camera["fov"] <= 175, "camera.fov", "expected 1 to 175 degrees")

    require(isinstance(manifest["objects"], list), "objects", "expected an array")
    object_ids = set()
    checked_assets = set()
    for index, item in enumerate(manifest["objects"]):
        field = f"objects[{index}]"
        fields(item, field, "id", "glbPath", "position", "rotationEulerDeg", "scale",
               "animationClip", "loopAnimation")
        nonblank(item["id"], f"{field}.id")
        require(item["id"] not in object_ids, f"{field}.id", f"duplicate ID {item['id']!r}")
        object_ids.add(item["id"])
        for key in ("position", "rotationEulerDeg", "scale"):
            vector(item[key], f"{field}.{key}")
        require(all(Vector(item["scale"])), f"{field}.scale", "components must be nonzero")
        if item["animationClip"] is not None:
            nonblank(item["animationClip"], f"{field}.animationClip")
        require(type(item["loopAnimation"]) is bool, f"{field}.loopAnimation", "expected true or false")

        nonblank(item["glbPath"], f"{field}.glbPath")
        require("\x00" not in item["glbPath"], f"{field}.glbPath", "invalid path")
        asset = (path.parent / item["glbPath"]).resolve()
        require(asset.suffix.lower() == ".glb" and asset.is_file(), f"{field}.glbPath",
                f"expected a readable .glb file at {asset}")
        if asset not in checked_assets:
            check_glb(asset)
            checked_assets.add(asset)
        item["glbPath"] = asset
    return manifest, frame_count


def run(args):
    if bpy.app.version < MIN_BLENDER:
        raise JobError(f"Blender 4.3 or newer is required. Found {bpy.app.version_string}.")
    if not bpy.app.background:
        raise JobError("Invoke Blender with --background")
    if not bpy.app.build_options.codec_ffmpeg:
        raise JobError("This Blender build does not include FFmpeg")
    manifest_path = args.manifest.resolve()
    output = args.out.absolute()
    require(output.suffix == ".mp4", "--out", "expected a path ending in .mp4")
    manifest, frame_count = read_manifest(manifest_path)
    output.parent.mkdir(parents=True, exist_ok=True)
    require(not output.is_dir(), "--out", "path points to a directory")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    if manifest["renderEngine"] == "CYCLES" and not bpy.app.build_options.cycles:
        raise JobError("This Blender build does not include Cycles")
    scene = bpy.context.scene
    scene.name = manifest["sceneId"]
    configure_scene(scene, manifest, frame_count)
    for item in manifest["objects"]:
        import_asset(scene, item, frame_count)
    build_camera(scene, manifest["camera"])
    build_lighting(scene, manifest["lightingPreset"], manifest["camera"]["target"])
    scene.frame_set(1)

    gpu = manifest["renderEngine"] == "CYCLES" and enable_cycles_gpu(scene)
    LOG.info("Rendering %d frames at %d fps and %dx%d using %s",
             frame_count, manifest["fps"], *manifest["resolution"], manifest["renderEngine"])
    try:
        render_movie(scene, output)
    except (JobError, RuntimeError) as error:
        if not gpu:
            if manifest["renderEngine"] == "EEVEE":
                raise JobError(f"EEVEE render failed. Check graphics support on this worker: {error}") from error
            raise
        LOG.warning("Cycles GPU render failed (%s). Retrying the job on CPU.", error)
        scene.cycles.device = "CPU"
        scene.frame_set(1)
        render_movie(scene, output)
    LOG.info("Wrote %s", output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True, help="Input JSON scene manifest")
    parser.add_argument("--out", type=Path, required=True, help="Output H.264 .mp4 path")
    parser.add_argument("--verbose", action="store_true", help="Log device probe details and tracebacks")
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    args = parser.parse_args(argv)
    logging.getLogger("glTFImporter").propagate = False
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format="%(asctime)s %(levelname)s %(name)s %(message)s")
    try:
        run(args)
    except (JobError, OSError) as error:
        LOG.error("%s", error, exc_info=args.verbose)
        return 1
    except KeyboardInterrupt:
        LOG.error("Render interrupted")
        return 130
    except Exception:
        LOG.exception("Unexpected Blender pipeline failure")
        return 1
    return 0


if __name__ == "__main__":
    status = main()
    if status:
        sys.stdout.flush()
        sys.stderr.flush()
        raise SystemExit(status)
