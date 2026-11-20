#!/usr/bin/env bash
# Ingest complete top-level drops. Failed drops stay in raw_drop for correction.
set -euo pipefail
export LC_ALL=C
scripts=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
root=$(cd -- "$scripts/.." && pwd -P)
scale=1
usage() {
    printf 'Usage: %s [--scale-multiplier NUMBER]\n' "${0##*/}"
}
case ${1:-} in
    --help|-h) usage; exit 0 ;;
    --scale-multiplier) [[ $# == 2 ]] || { usage >&2; exit 2; }; scale=$2 ;;
    '') ;;
    *) usage >&2; exit 2 ;;
esac
if ! [[ $scale =~ ^[+]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$ ]] ||
   ! awk -v x="$scale" 'BEGIN {exit !(x >= 0.000001 && x <= 1000000)}'; then
    printf 'Scale multiplier must be between 0.000001 and 1000000.\n' >&2
    exit 2
fi
scale=$(awk -v x="$scale" 'BEGIN {printf "%.17g", x}')
mkdir -p -- "$root"/{raw_drop,archive,ready_assets,renders}
blender=$("$scripts/bootstrap.sh")
exec 8>"$root/archive/.normalize.lock"
flock 8
shopt -s nullglob nocaseglob
log() { printf '[%s] normalize: %s\n' "$(date -u +%FT%TZ)" "$*" >&2; }

drop_records() {
    local drop=$1 file rel digest
    if [[ -d $drop ]]; then
        local invalid
        invalid=$(find "$drop" ! -type f ! -type d -print -quit) || return 1
        [[ -z $invalid ]] || return 1
        local files
        files=$(mktemp -- "$stage/files.XXXXXXXX") || return 1
        if ! find "$drop" -type f -printf '%P\0' | sort -z > "$files"; then
            rm -f -- "$files"
            return 1
        fi
        while IFS= read -r -d '' rel; do
            file="$drop/$rel"
            digest=$(sha256sum < "$file") || { rm -f -- "$files"; return 1; }
            printf '%s\0%s\0' "$rel" "${digest%% *}"
        done < "$files"
        rm -f -- "$files"
    else
        digest=$(sha256sum < "$drop") || return 1
        rel=${drop##*.}
        printf '%s\0%s\0' "${rel,,}" "${digest%% *}"
    fi
}

fingerprint() {
    local kind=standalone digest
    [[ ! -d $1 ]] || kind=bundle
    digest=$({ printf 'lightek-normalize-v1\0%s\0%s\0' "$kind" "$scale" && drop_records "$1"; } | sha256sum) || return 1
    printf '%s\n' "${digest%% *}"
}

ingest() {
    local drop=$1 primary digest verified destination receipt slot stem suffix
    local -a models=() bundle_args=() archived=()
    if [[ -L $drop ]]; then
        log "Rejected symlink: $drop"
        return 1
    elif [[ -d $drop ]]; then
        models=("$drop"/*.fbx "$drop"/*.glb "$drop"/*.gltf)
        if (( ${#models[@]} != 1 )) || [[ ! -f ${models[0]} || -L ${models[0]} ]]; then
            log "Bundle must contain exactly one top-level FBX, GLB or glTF: $drop"
            return 1
        fi
        primary=${models[0]}
        bundle_args=(--bundle "$drop")
    elif [[ -f $drop ]]; then
        case ${drop,,} in
            *.fbx|*.glb|*.gltf) primary=$drop ;;
            *) return 0 ;;
        esac
    else
        return 0
    fi
    digest=$(fingerprint "$drop") || { log "Cannot fingerprint $drop"; return 1; }
    receipt="$root/archive/$digest"
    # Remember the initial output name so a renamed duplicate resolves to the same GLB.
    if [[ ! -f $receipt/asset-name ]]; then
        mkdir -p -- "$receipt" || return 1
        stem=${primary##*/}; stem=${stem%.*}
        stem=${stem//[^a-zA-Z0-9_-]/-}
        suffix="${stem:0:48}--$digest.glb"
        printf '%s\n' "$suffix" > "$stage/$digest.name" &&
            mv -T -- "$stage/$digest.name" "$receipt/asset-name" || return 1
    fi
    IFS= read -r suffix < "$receipt/asset-name" || return 1
    [[ $suffix == *"--$digest.glb" && $suffix != */* ]] || return 1
    destination="$root/ready_assets/$suffix"
    if [[ ! -s $destination ]]; then
        log "Importing $primary"
        local pending="$stage/$digest.glb"
        if ! "$blender" --background --factory-startup --disable-autoexec --python-exit-code 1 \
                --python "$scripts/bpy_normalize.py" -- --input "$primary" --out "$pending" \
                --scale-multiplier "$scale" "${bundle_args[@]}"; then
            log "Conversion failed, source retained: $drop"
            return 1
        fi
        [[ -s $pending ]] || { log "Conversion produced no GLB: $drop"; return 1; }
        verified=$(fingerprint "$drop") || return 1
        if [[ $digest != "$verified" ]]; then
            log "Drop changed during conversion, source retained: $drop"
            return 1
        fi
        mv -T -- "$pending" "$destination" || return 1
    else
        log "Reusing existing GLB for $drop"
    fi
    archived=("$receipt/source/"*)
    if [[ ! -e $receipt/source ]]; then
        mkdir -- "$receipt/source" || return 1
        slot="$receipt/source"
    elif (( ${#archived[@]} == 0 )); then
        slot="$receipt/source"
    else
        mkdir -p -- "$receipt/duplicates" || return 1
        slot=$(mktemp -d -- "$receipt/duplicates/drop.XXXXXXXX") || return 1
    fi
    mv -T -- "$drop" "$slot/${drop##*/}" || return 1
    log "Ready: $destination"
}

stage=$(mktemp -d -- "$root/ready_assets/.normalize.XXXXXXXX")
trap 'rm -rf -- "$stage"' EXIT
failures=0
for drop in "$root/raw_drop/"*; do
    if ! ingest "$drop"; then
        log "Failed: $drop"
        failures=$((failures + 1))
    fi
done
if (( failures )); then
    log "$failures drop(s) failed"
    exit 1
fi
