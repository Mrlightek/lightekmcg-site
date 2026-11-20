"""Compose normalized assets in Blender and atomically publish a verified MP4."""
import argparse
import json
import logging
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))

import scene_renderer as worker
from bpy_normalize import gltf_metadata


def bounds(root, depsgraph):
    corners = []
    for obj in root.children_recursive:
        if obj.type == "MESH" and not obj.hide_render:
            evaluated = obj.evaluated_get(depsgraph)
            corners.extend(evaluated.matrix_world @ Vector(c) for c in evaluated.bound_box)
    if not corners:
        raise worker.JobError(f"{root.name}: no renderable meshes")
    low = Vector([min(c[i] for c in corners) for i in range(3)])
    high = Vector([max(c[i] for c in corners) for i in range(3)])
    return low, high


def camera_for_assets(roots, resolution):
    # Arrange assets side by side on Z=0 using their evaluated mesh bounds.
    depsgraph = bpy.context.evaluated_depsgraph_get()
    envelopes = [bounds(root, depsgraph) for root in roots]
    gap = max(0.12, max((high - low).length for low, high in envelopes) * 0.14)
    cursor = 0.0
    for root, (low, high) in zip(roots, envelopes):
        root.location += Vector((cursor - low.x, -(low.y + high.y) / 2, -low.z))
        cursor += high.x - low.x + gap
    bpy.context.view_layer.update()
    envelopes = [bounds(root, bpy.context.evaluated_depsgraph_get()) for root in roots]
    low = Vector([min(box[0][i] for box in envelopes) for i in range(3)])
    high = Vector([max(box[1][i] for box in envelopes) for i in range(3)])
    center = (low + high) * 0.5
    half_width = math.radians(39) / 2
    half_height = math.atan(math.tan(half_width) * resolution[1] / resolution[0])
    radius = max((high - low).length * 0.5, 0.05)
    distance = 1.18 * radius / math.sin(min(half_width, half_height))
    position = center + Vector((0.12, -1.0, 0.28)).normalized() * distance
    return {"position": position, "target": center, "fov": 39.0}


def check_movie(path, args):
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-count_frames", "-select_streams", "v:0",
         "-show_entries", "stream=codec_name,width,height,avg_frame_rate,nb_read_frames",
         "-of", "json", str(path)], capture_output=True, text=True, check=False,
    )
    if probe.returncode or probe.stderr.strip():
        raise worker.JobError(f"ffprobe failed: {probe.stderr.strip()}")
    streams = json.loads(probe.stdout).get("streams", [])
    expected = {"codec_name": "h264", "width": args.resolution[0], "height": args.resolution[1],
                "avg_frame_rate": f"{args.fps}/1", "nb_read_frames": str(args.end - args.start + 1)}
    if len(streams) != 1 or any(streams[0].get(key) != value for key, value in expected.items()):
        raise worker.JobError(f"MP4 does not match the requested output: {streams}")


def render(args):
    worker.integer(args.start, "--start", 1, worker.MAX_FRAMES)
    worker.integer(args.end, "--end", 1, worker.MAX_FRAMES)
    worker.require(args.start <= args.end, "frames", "--end must be at least --start")
    worker.integer(args.fps, "--fps", 1, 32_767)
    for size in args.resolution:
        worker.integer(size, "--resolution", 4, 65_536)
        worker.require(size % 2 == 0, "--resolution", "dimensions must be even")
    output = args.out.absolute()
    worker.require(output.suffix.lower() == ".mp4" and not output.is_dir(), "--out", "expected an MP4 file path")
    clip_overrides = {}
    for value in args.clip:
        index, separator, name = value.partition("=")
        if not separator or not index.isascii() or not index.isdecimal() or not name.strip():
            raise worker.JobError(f"Expected --clip ASSET_INDEX=NAME, got {value!r}")
        number = int(index)
        if number in clip_overrides or not 1 <= number <= len(args.asset):
            raise worker.JobError(f"Invalid or duplicate clip asset index: {number}")
        clip_overrides[number] = None if name == "-" else name

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    worker.configure_scene(scene, {"renderEngine": args.engine, "resolution": args.resolution, "fps": args.fps}, args.end)
    roots = []
    for index, asset in enumerate(args.asset, 1):
        asset = asset.resolve(strict=True)
        worker.require(asset.suffix.lower() == ".glb", "--asset", f"normalize {asset.name} before rendering")
        worker.check_glb(asset)
        clips = gltf_metadata(asset).get("animations", [])
        default_clip = (clips[0].get("name") or "Anim_0") if clips else None
        asset_id = f"{index}: {asset.stem}"
        worker.import_asset(scene, {"id": asset_id, "glbPath": asset,
                                    "position": (0, 0, 0), "rotationEulerDeg": (0, 0, 0),
                                    "scale": (1, 1, 1), "animationClip": clip_overrides.get(index, default_clip),
                                    "loopAnimation": args.loop}, args.end)
        roots.append(next(obj for obj in scene.objects if obj.get("manifest_id") == asset_id))
    scene.frame_set(args.start)
    camera = camera_for_assets(roots, args.resolution)
    worker.build_camera(scene, camera)
    worker.build_lighting(scene, args.lighting, camera["target"])
    scene.frame_start = args.start

    gpu = args.engine == "CYCLES" and worker.enable_cycles_gpu(scene)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".verify-shot-", dir=output.parent) as pending:
        movie = Path(pending) / "shot.mp4"
        try:
            worker.render_movie(scene, movie)
            check_movie(movie, args)
        except (RuntimeError, worker.JobError) as error:
            if not gpu:
                raise
            worker.LOG.warning("Cycles GPU error (%s). Retrying on CPU.", error)
            scene.cycles.device = "CPU"
            scene.frame_set(args.start)
            worker.render_movie(scene, movie)
            check_movie(movie, args)
        os.replace(movie, output)
    worker.LOG.info("Wrote %s (%d frames at %d fps)", output, args.end - args.start + 1, args.fps)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--asset", action="append", type=Path, required=True, help="Normalized GLB. Repeat for more assets.")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--engine", choices=["EEVEE", "CYCLES"], default="CYCLES")
    parser.add_argument("--start", type=int, default=1)
    parser.add_argument("--end", type=int, required=True, help="Inclusive end frame")
    parser.add_argument("--fps", type=int, default=24)
    parser.add_argument("--resolution", nargs=2, type=int, default=[1280, 720], metavar=("WIDTH", "HEIGHT"))
    parser.add_argument("--lighting", choices=sorted(worker.LIGHTING), default="studio_soft")
    parser.add_argument("--clip", action="append", default=[], metavar="ASSET_INDEX=NAME",
                        help="1-based asset index. Defaults to the first clip. Use INDEX=- for rest pose.")
    parser.add_argument("--loop", action="store_true", help="Loop the selected clips")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    logging.getLogger("glTFImporter").propagate = False
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    try:
        render(args)
    except (OSError, RuntimeError, ValueError, worker.JobError) as error:
        raise SystemExit(f"render: {error}") from error


if __name__ == "__main__":
    main()
