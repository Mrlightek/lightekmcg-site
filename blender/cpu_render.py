"""Bounded CPU rendering with per-operation, content-verified frame checkpoints."""
import bpy
import hashlib
import json
import os
from pathlib import Path
import resource
import shutil
import subprocess
import time

PROFILE = 'cpu_economy'
CACHE_LIMIT = 256 * 1024 * 1024


def atomic_json(path, value):
    temporary = str(path) + '.part'
    with open(temporary, 'w') as handle:
        json.dump(value, handle)
    os.replace(temporary, path)


def checksum(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def fingerprint(manifest):
    digest = hashlib.sha256(json.dumps(manifest, sort_keys=True).encode())
    digest.update(bpy.app.version_string.encode())
    for path in sorted(Path(__file__).parent.glob('*.py')):
        digest.update(path.name.encode()); digest.update(checksum(path).encode())
    sources = [manifest.get('native_template_path')]
    for item in manifest['scene'].get('objects', []):
        definition = item.get('definition', {})
        sources.extend([definition.get('asset_path'), definition.get('performance', {}).get('audio_path')])
    for source in sorted(set(path for path in sources if path)):
        path = Path(source)
        digest.update(str(path).encode()); digest.update(checksum(path).encode())
        # Packed/native bundles may use relative textures beside the source.
        if manifest.get('native_template_path') == source and 'native-bundle' in path.parts:
            base = next(parent for parent in path.parents if parent.name == 'native-bundle')
            for dependency in sorted(p for p in base.rglob('*') if p.is_file()):
                digest.update(str(dependency.relative_to(base)).encode()); digest.update(checksum(dependency).encode())
    return digest.hexdigest()


def configure(settings):
    if settings.get('compute_profile') != PROFILE:
        return
    scene = bpy.context.scene
    if any(obj.rigid_body or obj.particle_systems or any(mod.type in {'CLOTH','FLUID','SOFT_BODY','DYNAMIC_PAINT'} for mod in obj.modifiers) for obj in scene.objects):
        raise ValueError('Use the custom render profile for stateful simulations, or bake them into geometry before CPU checkpoint rendering')
    width = int(settings.get('resolution_x', 512)); height = int(settings.get('resolution_y', 288))
    if min(width, height) < 16 or max(width, height) > 512:
        raise ValueError('CPU economy output must fit within 512 pixels per side')
    scene.render.engine = 'CYCLES'; scene.cycles.device = 'CPU'
    scene.cycles.samples = max(1, min(8, int(settings.get('samples', 8))))
    scene.cycles.use_denoising = False
    scene.render.threads_mode = 'FIXED'; scene.render.threads = 1
    scene.render.resolution_x = width; scene.render.resolution_y = height; scene.render.resolution_percentage = 100
    scene.render.use_persistent_data = False
    editor = scene.sequence_editor
    if editor:
        strips = list(editor.strips_all if hasattr(editor, 'strips_all') else editor.sequences_all)
        if any(strip.type == 'SOUND' for strip in strips) and not any(strip.type not in {'SOUND','META'} for strip in strips):
            scene.render.use_sequencer = False


def movie(manifest, directory):
    scene = bpy.context.scene; root = Path(directory); frames = root / 'cpu-frames'
    first, last = scene.frame_start, scene.frame_end; total = last - first + 1
    if not 1 <= first or not 1 <= total <= 2400:
        raise ValueError('CPU movie needs 1–2400 ordered frames')
    if not frames.exists(): frames.mkdir(mode=0o700)
    key = fingerprint(manifest); journal_path = frames / 'checkpoint.json'; journal = {}
    if journal_path.exists():
        try: journal = json.loads(journal_path.read_text())
        except (ValueError, OSError): journal = {}
    if journal.get('fingerprint') != key:
        for path in frames.iterdir():
            if path.is_file(): path.unlink()
        journal = {'fingerprint': key, 'frames': {}}
    started = time.monotonic(); cpu_start = time.process_time(); reused = 0; complete = 0
    def report(phase):
        atomic_json(root / 'cpu-progress.json', {'profile': PROFILE, 'phase': phase, 'completed_frames': complete,
            'total_frames': total, 'reused_frames': reused, 'elapsed_seconds': round(time.monotonic()-started, 3),
            'cpu_seconds': round(time.process_time()-cpu_start, 3), 'blender_peak_rss_bytes': resource.getrusage(resource.RUSAGE_SELF).ru_maxrss * 1024})
    report('rendering_frames')
    scene.render.image_settings.file_format = 'PNG'; scene.render.image_settings.color_mode = 'RGBA'
    size = sum(p.stat().st_size for p in frames.glob('frame-*.png'))
    for frame in range(first, last+1):
        scene.frame_set(frame)
        path = frames / f'frame-{frame:06d}.png'; saved = journal['frames'].get(str(frame))
        if saved and path.is_file() and saved == checksum(path):
            reused += 1
        else:
            if size >= CACHE_LIMIT or shutil.disk_usage(root).free < 512*1024*1024:
                raise RuntimeError('CPU frame cache reached its storage budget. Shorten the shot or free worker storage before resuming.')
            old_size = path.stat().st_size if path.exists() else 0
            scene.render.filepath = str(frames / 'current.part.png')
            bpy.ops.render.render(write_still=True)
            temporary = frames / 'current.part.png'
            if size-old_size+temporary.stat().st_size > CACHE_LIMIT:
                temporary.unlink(); raise RuntimeError('CPU frame cache exceeds its 256 MB budget. Shorten this shot.')
            os.replace(temporary, path); size += path.stat().st_size-old_size
            journal['frames'][str(frame)] = checksum(path); atomic_json(journal_path, journal)
        complete += 1; report('rendering_frames')
    report('encoding')
    rate = scene.render.fps / scene.render.fps_base
    target = root / 'movie.part.mp4'
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-framerate', str(rate), '-start_number', str(first),
        '-i', str(frames / 'frame-%06d.png'), '-frames:v', str(total), '-c:v', 'libx264', '-threads', '1',
        '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(target)], check=True, timeout=180)
    os.replace(target, root / 'movie.mp4'); scene.render.filepath = str(root / 'movie.mp4')
    report('picture_encoded')


def has_audio(scene):
    editor = scene.sequence_editor
    if not editor: return False
    strips = editor.strips_all if hasattr(editor, 'strips_all') else editor.sequences_all
    return any(strip.type == 'SOUND' for strip in strips)


def completed(directory):
    path = Path(directory) / 'cpu-progress.json'
    payload = json.loads(path.read_text()); payload['phase'] = 'completed'
    payload['blender_peak_rss_bytes'] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss * 1024
    atomic_json(path, payload)
