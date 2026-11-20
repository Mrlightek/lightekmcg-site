#!/usr/bin/env bash
# Generate a MakeHuman model, acquire a skinned Mixamo motion, and render a shot.
set -euo pipefail
umask 077

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
tools=$(cd -- "$here/../scripts" && pwd -P)
source "$here/mixamo_auth_guard.sh"

usage() {
    cat <<'HELP'
Usage: run_pipeline.sh --job-dir DIR --out SHOT.mp4 --animation TITLE
  [--animation-id MIXAMO_ID] [--animated-fbx FILE] [--prop READY.glb ...]
  [--engine CYCLES|EEVEE] [--first N] [--last N] [--fps N] [--resolution W H]
  [--gender 0..1] [--age 0..1] [--weight 0..1] [--height 0..1]
--animated-fbx resumes from an already downloaded, skinned animation.
Either --animation or --animated-fbx is required. Frames are inclusive.
HELP
}

log() { printf '[%s] character-pipeline: %s\n' "$(date -u +%FT%TZ)" "$*" >&2; }
die() { log "$*"; exit 2; }
non_auth_step() {
    local status
    if env -u MIXAMO_EMAIL -u MIXAMO_PASSWORD "$@"; then return 0; else status=$?; fi
    if (( status == 42 )); then
        log 'A non-authentication step returned reserved exit 42'
        return 1
    fi
    return "$status"
}

job= output= animation= animation_id= downloaded=
engine=CYCLES first=1 last=96 fps=24 width=1280 height=720
gender=0.5 age=0.5 weight=0.5 body_height=0.5
props=()
while (( $# )); do
    case $1 in
        --help|-h) usage; exit 0 ;;
        --resolution)
            (( $# >= 3 )) || die "$1 requires two values"
            width=$2; height=$3; shift 3; continue ;;
        --job-dir|--out|--animation|--animation-id|--animated-fbx|--engine|--first|--last|--fps|--gender|--age|--weight|--height|--prop)
            (( $# >= 2 )) || die "$1 requires a value" ;;
        *) die "Unknown option $1" ;;
    esac
    case $1 in
        --job-dir) job=$2 ;;
        --out) output=$2 ;;
        --animation) animation=$2 ;;
        --animation-id) animation_id=$2 ;;
        --animated-fbx) downloaded=$2 ;;
        --engine) engine=$2 ;;
        --first) first=$2 ;;
        --last) last=$2 ;;
        --fps) fps=$2 ;;
        --gender) gender=$2 ;;
        --age) age=$2 ;;
        --weight) weight=$2 ;;
        --height) body_height=$2 ;;
        --prop) props+=(--asset "$2") ;;
    esac
    shift 2
done
[[ -n $job && ${output,,} == *.mp4 && ( -n $animation || -n $downloaded ) ]] || { usage >&2; exit 2; }
[[ $engine == CYCLES || $engine == EEVEE ]] || die 'Engine must be CYCLES or EEVEE'
for integer in "$first" "$last" "$fps" "$width" "$height"; do
    [[ $integer =~ ^[1-9][0-9]{0,4}$ ]] || die "Invalid frame, FPS, or dimension: $integer"
done
(( first <= last && last - first < 3600 && fps <= 60 && width >= 64 && width <= 3840 &&
   height >= 64 && height <= 2160 && width % 2 == 0 && height % 2 == 0 )) ||
    die 'Use up to 3600 frames, up to 60 FPS and even dimensions from 64×64 to 3840×2160'
[[ -z $animation_id || $animation_id =~ ^[0-9]+$ ]] || die 'Mixamo animation ID must be numeric'
for fraction in "$gender" "$age" "$weight" "$body_height"; do
    if ! [[ $fraction =~ ^([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]] ||
       ! awk -v x="$fraction" 'BEGIN {exit !(x >= 0 && x <= 1)}'; then
        die "MakeHuman morphs take values from 0 to 1: $fraction"
    fi
done
if [[ -n $downloaded ]]; then
    [[ -s $downloaded && ${downloaded,,} == *.fbx ]] || die '--animated-fbx must be a nonempty FBX file'
    downloaded=$(realpath -- "$downloaded")
fi

blender=$(non_auth_step "$tools/bootstrap.sh")
mkdir -p -- "$job"
job=$(cd -- "$job" && pwd -P)
exec 8>"$job/.pipeline.lock"
flock -n 8 || { log 'This job directory is already in use'; exit 1; }
stage=$(mktemp -d -- "$job/.run.XXXXXXXX")
trap 'rm -rf -- "$stage"' EXIT

if [[ -z $downloaded ]]; then
    if [[ -z ${MIXAMO_PYTHON:-} ]]; then
        MIXAMO_PYTHON=$(non_auth_step "$here/setup_character.sh")
    fi
    export MIXAMO_PYTHON
    log 'Checking the saved Mixamo browser session'
    mixamo_auth_guard

    log 'Generating a weighted MakeHuman character'
    non_auth_step "$MIXAMO_PYTHON" "$here/generate_character.py" --out "$stage/source.fbx" \
        --gender "$gender" --age "$age" --weight "$weight" --height "$body_height"
    # Keep the rig intact and embed textures for Mixamo's FBX uploader.
    non_auth_step "$blender" --background --factory-startup --python-exit-code 1 --python "$tools/bpy_normalize.py" -- \
        --input "$stage/source.fbx" --bundle "$stage" --out "$stage/asset.glb" --mixamo-out "$stage/upload.fbx"
    mv -T -- "$stage/upload.fbx" "$job/character.fbx"

    transfer=(--character "$job/character.fbx" --out "$stage/animated.fbx" --query "$animation" --fps 30)
    if [[ -n $animation_id ]]; then transfer+=(--animation-id "$animation_id"); fi
    log 'Uploading character, selecting animation and downloading FBX with skin'
    status=0
    env -u MIXAMO_EMAIL -u MIXAMO_PASSWORD "$MIXAMO_PYTHON" "$here/browser.py" transfer "${transfer[@]}" || status=$?
    if (( status == 42 )); then
        mixamo_auth_guard
        status=0
        env -u MIXAMO_EMAIL -u MIXAMO_PASSWORD "$MIXAMO_PYTHON" "$here/browser.py" transfer "${transfer[@]}" || status=$?
    fi
    if (( status == 42 )); then
        mixamo_login_instructions "$MIXAMO_PYTHON"
        exit 42
    elif (( status == 3 )); then
        transfer[3]="$job/animated.fbx"
        log 'Mixamo requires manual rig marker placement. Run this in the graphical desktop session:'
        printf '  %q ' "$MIXAMO_PYTHON" "$here/browser.py" rig "${transfer[@]}" >&2
        printf '\n' >&2
        printf '%s\n' 'Then rerun the pipeline with --animated-fbx pointing to the downloaded file.' >&2
        exit 3
    elif (( status != 0 )); then
        exit "$status"
    fi
    mv -T -- "$stage/animated.fbx" "$job/animated.fbx"
    downloaded="$job/animated.fbx"
fi

log 'Normalizing the skinned animation for Blender scene assembly'
non_auth_step "$blender" --background --factory-startup --python-exit-code 1 --python "$tools/bpy_normalize.py" -- \
    --input "$downloaded" --out "$stage/character.glb" --require-animation
mv -T -- "$stage/character.glb" "$job/character.glb"
log 'Assembling and rendering the scene'
non_auth_step "$blender" --background --factory-startup --python-exit-code 1 --python "$here/assemble_scene.py" -- \
    --asset "$job/character.glb" "${props[@]}" --out "$output" --engine "$engine" \
    --start "$first" --end "$last" --fps "$fps" --resolution "$width" "$height" --loop
log "Render verified at $output"
