#!/usr/bin/env bash
set -euo pipefail
umask 077

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
job=${OUTPUT_DIR:?"Set OUTPUT_DIR to the job directory"}
mode=${1:---full}
[[ $# -le 1 && ( $mode == --full || $mode == --render-only ) ]] || {
    printf '%s\n' 'Usage: OUTPUT_DIR=/path script/run_pipeline.sh [--full|--render-only]' >&2
    exit 2
}
mkdir -p -- "$job"
job=$(cd -- "$job" && pwd -P)
exec 8>"$job/.character-pipeline.lock"
flock -n 8 || { printf '%s\n' 'Pipeline already running in this directory' >&2; exit 1; }
stage=$(mktemp -d -- "$job/.render.XXXXXXXX")
trap 'test -z "$stage" || rm -rf -- "$stage"' EXIT

# Exit 42 is reserved for the Mixamo wrapper.
step() {
    local code=0
    env -u MIXAMO_EMAIL -u MIXAMO_PASSWORD "$@" || code=$?
    if (( code == 42 )); then code=1; fi
    return "$code"
}
blender=${BLENDER_BIN:-blender}

if [[ $mode == --full ]]; then
    printf '%s\n' '[pipeline] Generating character'
    step timeout --kill-after=10s 180s "${MAKEHUMAN_PYTHON:-python3}" "$here/generate_character.py" \
        --output "$job/character.fbx" --gender "${GENDER:-0.5}" --height "${HEIGHT:-0.5}" --muscle "${MUSCLE:-0.5}"
    printf '%s\n' '[pipeline] Preparing textured FBX for Mixamo'
    step timeout --kill-after=10s 180s "$blender" --background --factory-startup --python-exit-code 1 \
        --python "$here/assemble_and_render.py" -- --character "$job/character.fbx" \
        --pack-fbx "$stage/upload.fbx"
    printf '%s\n' '[pipeline] Applying Mixamo animation'
    "$here/mixamo_wrapper.sh" "$stage/upload.fbx" "$job/animated.fbx"
fi

[[ -s $job/animated.fbx ]] || { printf '%s\n' 'Render requires animated.fbx' >&2; exit 1; }
printf '%s\n' '[pipeline] Rendering frames in Blender'
step timeout --kill-after=10s 1800s "$blender" --background --factory-startup --python-exit-code 1 \
    --python "$here/assemble_and_render.py" -- --character "$job/animated.fbx" \
    --output-dir "$stage" --frames "${FRAMES:-30}" --resolution "${RENDER_RESOLUTION:-640x360}" \
    --texture-dir "$job/textures"
printf '%s\n' '[pipeline] Encoding MP4 preview'
step timeout --kill-after=10s 180s ffmpeg -hide_banner -loglevel error -nostdin -threads 2 -framerate 30 \
    -start_number 1 -i "$stage/frame_%06d.png" -c:v libx264 -threads 2 -pix_fmt yuv420p \
    -movflags +faststart "$stage/preview.mp4"
[[ -s $stage/preview.mp4 ]] || exit 1
mv -T -- "$stage" "$job/render-${stage##*.}"
latest="$job/render-${stage##*.}"
stage=
cp -- "$latest/preview.mp4" "$job/.preview.mp4"
mv -fT -- "$job/.preview.mp4" "$job/preview.mp4"
printf '[pipeline] Frames and preview saved to %s\n' "$latest"
