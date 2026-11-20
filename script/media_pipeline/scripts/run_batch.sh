#!/usr/bin/env bash
# Each non-comment line is a tab-delimited render_shot argument list. No shell evaluation.
set -euo pipefail
scripts=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
root=$(cd -- "$scripts/.." && pwd -P)
log() { printf '[%s] batch: %s\n' "$(date -u +%FT%TZ)" "$*" >&2; }
if (( $# != 1 )) || [[ $1 == --help || $1 == -h ]]; then
    printf 'Usage: %s SHOTS.tsv\nRelative paths inside SHOTS.tsv are based on the pipeline directory.\n' "${0##*/}"
    (( $# == 1 )) && [[ $1 == --help || $1 == -h ]] && exit 0
    exit 2
fi
batch=$(realpath -e -- "$1") || exit 2
[[ -f $batch && -r $batch ]] || { log "Unreadable batch file: $batch"; exit 2; }
cd -- "$root"
line_no=0
count=0
failures=0
while IFS= read -r line || [[ -n $line ]]; do
    line_no=$((line_no + 1))
    line=${line%$'\r'}
    if [[ $line =~ ^[[:space:]]*(#|$) ]]; then
        continue
    fi
    count=$((count + 1))
    if [[ $line == $'\t'* || $line == *$'\t' || $line == *$'\t\t'* ]]; then
        log "Line $line_no has an empty argument"
        failures=$((failures + 1))
        continue
    fi
    IFS=$'\t' read -r -a arguments <<< "$line"
    log "Starting shot $count (line $line_no)"
    if "$scripts/render_shot.sh" "${arguments[@]}" </dev/null; then
        log "Shot $count succeeded"
    else
        status=$?
        log "Shot $count failed (exit $status)"
        failures=$((failures + 1))
    fi
done < "$batch"
log "$((count - failures)) succeeded, $failures failed"
(( count > 0 && failures == 0 ))
