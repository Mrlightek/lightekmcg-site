#!/usr/bin/env bash
# Install the operator's pinned MakeHuman and Mixamo browser dependencies.
set -euo pipefail
umask 077
state=${LIGHTEK_CHARACTER_HOME:-"${XDG_DATA_HOME:-$HOME/.local/share}/lightek-character"}
revision=8bdb0a3ed91fdc1fadc469701e09ecb0bdb7aefd
browser_revision=1.62.0
mkdir -p -- "$state"
state=$(cd -- "$state" && pwd -P)
if ! command -v flock >/dev/null; then
    printf 'setup_character: install util-linux with apt-get first\n' >&2
    exit 1
fi
exec 9>"$state/install.lock"
flock 9
python="$state/venv/bin/python"
export PLAYWRIGHT_BROWSERS_PATH=${PLAYWRIGHT_BROWSERS_PATH:-"$state/browsers"}
if [[ -f $state/installed-$revision-$browser_revision && -x $python ]]; then
    printf '%s\n' "$python"
    exit 0
fi
apt_packages=()
command -v git >/dev/null || apt_packages+=(git)
command -v python3 >/dev/null || apt_packages+=(python3)
if ! command -v python3 >/dev/null || ! python3 -c 'import ensurepip' >/dev/null 2>&1; then
    apt_packages+=(python3-venv)
fi
if (( ${#apt_packages[@]} )); then
    prefix=()
    if (( EUID != 0 )); then
        command -v sudo >/dev/null || { printf 'setup_character: install %s as a server administrator\n' "${apt_packages[*]}" >&2; exit 1; }
        prefix=(sudo)
    fi
    "${prefix[@]}" apt-get update >&2
    "${prefix[@]}" apt-get install -y --no-install-recommends "${apt_packages[@]}" >&2
fi

if [[ ! -x $python ]]; then
    python3 -m venv "$state/venv"
fi
"$python" -m pip install --disable-pip-version-check \
    'makehuman-mcp==0.1.3' "playwright==$browser_revision" 'beautifulsoup4==4.14.2' >&2

if [[ ! -f $state/mixamo-mcp-$revision/screens/upload.py ]]; then
    stage=$(mktemp -d -- "$state/.mixamo.XXXXXXXX")
    trap 'rm -rf -- "$stage"' EXIT
    git -C "$stage" init -q
    git -C "$stage" fetch -q --depth=1 https://github.com/V1xel/mixamo-mcp.git "$revision"
    git -C "$stage" checkout -q --detach FETCH_HEAD
    [[ $(git -C "$stage" rev-parse HEAD) == "$revision" ]]
    mv -T -- "$stage" "$state/mixamo-mcp-$revision"
    trap - EXIT
fi

"$python" -m playwright install chromium >&2
if ! "$python" -c 'from playwright.sync_api import sync_playwright; p=sync_playwright().start(); p.chromium.launch().close(); p.stop()' >/dev/null 2>&1; then
    "$python" -m playwright install-deps chromium >&2
    "$python" -c 'from playwright.sync_api import sync_playwright; p=sync_playwright().start(); p.chromium.launch().close(); p.stop()' >&2
fi
touch -- "$state/installed-$revision-$browser_revision"
printf '%s\n' "$python"
