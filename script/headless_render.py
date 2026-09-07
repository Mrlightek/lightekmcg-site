import bpy
import json
import sys
import os

def render_scene_from_manifest(manifest_path, output_mp4_path):
    if not os.path.exists(manifest_path):
        print(f"Error: Manifest file not found at {manifest_path}")
        sys.exit(1)

    # 1. Access active scene
    scene = bpy.context.scene

    # 2. Configure Render Engine & Output Settings
    scene.render.engine = 'BLENDER_EEVEE_NEXT'  # Or 'CYCLES'
    scene.render.fps = 24
    scene.render.image_settings.file_format = 'FFMPEG'
    scene.render.filepath = output_mp4_path

    # 3. Configure Video Encoding Options
    scene.render.ffmpeg.format = 'MPEG4'
    scene.render.ffmpeg.codec = 'H264'
    scene.render.ffmpeg.constant_rate_factor = 'MEDIUM'
    
    # 4. Configure Audio Multiplexing (Crucial for VSE sound output)
    scene.render.ffmpeg.audio_codec = 'AAC'
    scene.render.ffmpeg.audio_bitrate = 192

    # 5. Calculate Scene Frame Range based on Manifest Lines
    with open(manifest_path, 'r') as f:
        data = json.load(f)
    
    lines = data.get('script_data', [])
    if lines:
        last_frame = lines[-1].get('start_frame', 100) + 96 # Add 4-second padding
        scene.frame_start = 1
        scene.frame_end = last_frame
    
    print(f"--- STARTING RENDER: Frames {scene.frame_start} to {scene.frame_end} ---")
    print(f"--- OUTPUT FILE: {output_mp4_path} ---")

    # 6. Execute Headless Render Sequence
    bpy.ops.render.render(animation=True)
    print("--- RENDER COMPLETE ---")

# Parse command-line args passed after '--' in Blender execution
if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    manifest = args[0] if len(args) > 0 else "blender_manifest.json"
    output_video = args[1] if len(args) > 1 else "./output_scene.mp4"

    render_scene_from_manifest(manifest, output_video)