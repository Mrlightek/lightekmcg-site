#!/usr/bin/env bash
# All worker access to the saved Mixamo session is serialized here.
set -euo pipefail
umask 077
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo=${MIXAMO_DIR:-"$HOME/mixamo-mcp"}
python=${MIXAMO_PYTHON:-python}
name=${MIXAMO_ANIMATION:-Walking}
id=${MIXAMO_ANIMATION_ID:-}

fail() { printf '[mixamo] %s\n' "$*" >&2; exit 1; }
login() {
    printf '%s\n' 'Mixamo sign-in required. Run this as the Studio worker user, finish signing in, then quit the Mixamo CLI:' \
        'cd ~/mixamo-mcp && python main.py' >&2
    exit 42
}

[[ $# == 2 && -s $1 ]] || fail 'Usage: mixamo_wrapper.sh CHARACTER.fbx ANIMATED.fbx'
source_fbx=$(realpath -- "$1")
output=$(realpath -m -- "$2")
[[ $source_fbx != "$output" && $source_fbx == *.fbx && $output == *.fbx ]] || fail 'Provide two distinct FBX paths'
[[ -z $id || $id =~ ^[0-9]{1,20}$ ]] || fail 'Animation ID must contain 1–20 digits'
[[ -f $repo/main.py ]] || fail "Install mixamo-mcp in $repo"
cd -- "$repo"
# Separate jobs must never switch one another's character or animation.
exec 9>.lightek-studio.lock
flock -w 330 9 || fail 'Mixamo is busy. Retry after the other transfer finishes.'
transfer=$(mktemp -d -- "$(dirname -- "$output")/.mixamo.XXXXXXXX")
trap 'rm -rf -- "$transfer"' EXIT

cli() {
    local result code=0
    result=$(env -u MIXAMO_EMAIL -u MIXAMO_PASSWORD timeout --kill-after=10s 300s \
        "$python" main.py "$@" 2>&1) || code=$?
    # Match explicit negative auth messages before positive ones.
    if (( code == 42 )) || grep -Eiq \
        'logged in[[:space:]]*[:=][[:space:]]*(false|no)|not (logged|signed) in|unauthenticated|session[[:space:]]+(has[[:space:]]+|is[[:space:]]+)?expired|login required|sign-in required' <<<"$result"; then
        login
    fi
    if (( code != 0 )); then
        printf '%s\n' "$result" >&2
        return 1
    fi
    printf '%s\n' "$result"
}

case ${MIXAMO_CLI_MODE:-auto} in
    auto)
        mode=positional
        if grep -q 'target=input_loop' main.py && [[ -d screens ]]; then mode=interactive; fi
        ;;
    positional|interactive) mode=$MIXAMO_CLI_MODE ;;
    *) fail 'MIXAMO_CLI_MODE must be auto, positional or interactive' ;;
esac

if [[ $mode == interactive ]]; then
    code=0
    env -u MIXAMO_EMAIL -u MIXAMO_PASSWORD timeout --kill-after=10s 400s \
        "$python" "$here/mixamo_cli.py" transfer -- "$source_fbx" "$transfer/animated.fbx" "$name" "$id" || code=$?
    if (( code == 42 )); then login; fi
    (( code == 0 )) || fail "Mixamo transfer failed (exit $code)"
else
    cli status >"$transfer/status"
    grep -Eiq 'logged in[[:space:]]*[:=][[:space:]]*(true|yes)|session active|^logged in[.!]?$|^authenticated([.!]|[[:space:]]*[:=][[:space:]]*true)?$' "$transfer/status" ||
        fail 'Mixamo status did not confirm authentication'
    cli upload "$source_fbx"
    if [[ -z $id ]]; then
        cli list "$name" >"$transfer/list"
        id=$("$python" "$here/mixamo_cli.py" match -- "$name" "$transfer/list")
    fi
    cli select "$id"
    cli download "$transfer/animated.fbx" format=fbx skin=true fps=30
fi
[[ -s $transfer/animated.fbx ]] || fail 'Mixamo did not write an animated FBX'
mv -fT -- "$transfer/animated.fbx" "$output"
printf '[mixamo] Saved %s\n' "$output"
