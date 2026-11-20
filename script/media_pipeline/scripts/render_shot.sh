#!/usr/bin/env bash
# Render one shot. Relative asset and output paths use the caller's directory.
set -euo pipefail
scripts=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    cat <<'HELP'
Usage: render_shot.sh --asset FILE.glb [--asset FILE.glb ...] --out FILE.mp4 --end FRAME
  [--engine EEVEE|CYCLES] [--start FRAME] [--fps FPS] [--resolution WIDTH HEIGHT]
  [--lighting studio_soft|dramatic_rim|outdoor_day] [--clip ASSET_INDEX=NAME] [--loop]
Frame bounds are inclusive and begin at 1. Asset indexes for --clip start at 1.
HELP
    exit 0
fi
threads=${BLENDER_THREADS:-0}
if ! [[ $threads =~ ^[0-9]{1,3}$ ]] || (( 10#$threads > 256 )); then
    printf 'BLENDER_THREADS must be between 0 and 256\n' >&2
    exit 2
fi
blender=$("$scripts/bootstrap.sh")
exec "$blender" --background --factory-startup --disable-autoexec --threads "$threads" \
    --python-exit-code 1 --python "$scripts/bpy_render.py" -- "$@"
