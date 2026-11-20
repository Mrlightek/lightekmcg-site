#!/usr/bin/env bash
# Install missing runtime dependencies on Ubuntu/Debian. Prints the usable Blender path.
set -euo pipefail
export LC_ALL=C

die() { printf 'bootstrap: %s\n' "$*" >&2; exit 1; }
installer_root=${PIPELINE_TOOL_DIR:-"${XDG_DATA_HOME:-$HOME/.local/share}/lightek-media"}
version=${BLENDER_VERSION:-4.5.16}
[[ $version =~ ^4\.5\.[0-9]+$ ]] || die "BLENDER_VERSION must be a 4.5 LTS release"
managed="$installer_root/blender-$version/blender"

apt_install() {
    command -v apt-get >/dev/null || die "Automatic system dependency installation requires apt-get"
    local -a prefix=()
    if (( EUID != 0 )); then
        command -v sudo >/dev/null || die "Run bootstrap as root or install these packages: $*"
        prefix=(sudo)
    fi
    "${prefix[@]}" apt-get update >&2
    "${prefix[@]}" apt-get install -y --no-install-recommends "$@" >&2
}

probe() {
    [[ -x $1 ]] && "$1" --background --factory-startup --disable-autoexec --threads 1 \
        --python-exit-code 11 --python-expr 'import bpy; assert bpy.app.version >= (4, 3, 0); assert bpy.app.build_options.codec_ffmpeg and bpy.app.build_options.cycles; bpy.ops.import_scene.fbx.get_rna_type(); bpy.ops.import_scene.gltf.get_rna_type(); bpy.ops.export_scene.gltf.get_rna_type()' \
        >/dev/null 2>&1
}

install_if_missing=()
command -v flock >/dev/null || install_if_missing+=(util-linux)
command -v ffprobe >/dev/null && command -v ffmpeg >/dev/null || install_if_missing+=(ffmpeg)
if (( ${#install_if_missing[@]} )); then
    apt_install "${install_if_missing[@]}"
fi

if [[ -n ${BLENDER_BIN:-} ]]; then
    executable=$(command -v -- "$BLENDER_BIN") || die "BLENDER_BIN does not resolve: $BLENDER_BIN"
    executable=$(realpath -- "$executable")
    probe "$executable" || die "BLENDER_BIN is unusable; need Blender 4.3+ with Cycles, FFmpeg and FBX/glTF operators"
    printf '%s\n' "$executable"
    exit 0
fi
if probe "$managed"; then
    realpath -- "$managed"
    exit 0
fi
system_bin=$(command -v blender || true)
if [[ -n $system_bin ]] && probe "$system_bin"; then
    realpath -- "$system_bin"
    exit 0
fi

[[ $(uname -s):$(uname -m) == Linux:x86_64 ]] ||
    die "The managed Blender download is for Linux x86_64. Set BLENDER_BIN to a compatible build on this host."
mkdir -p -- "$installer_root"
exec 9>"$installer_root/.install.lock"
flock 9
if probe "$managed"; then
    realpath -- "$managed"
    exit 0
fi

# Portable Blender still links to the host's X11/EGL libraries, even in background mode.
apt_install ca-certificates curl xz-utils libgl1 libegl1 libgl1-mesa-dri \
    libx11-6 libxext6 libxi6 libxfixes3 libxrender1 libxkbcommon0 libxkbcommon-x11-0 \
    libsm6 libice6 libxrandr2 libxcb1 libxxf86vm1 libxtst6 libpulse0 libxcursor1 libxinerama1 libdbus-1-3

archive="blender-$version-linux-x64.tar.xz"
base=https://download.blender.org/release/Blender4.5
stage=$(mktemp -d -- "$installer_root/.install.XXXXXXXX")
trap 'rm -rf -- "$stage"' EXIT
download() {
    curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' \
        --retry 3 --connect-timeout 20 --output "$stage/$1" "$base/$1"
}
printf 'bootstrap: downloading Blender %s\n' "$version" >&2
if [[ $version == 4.5.16 ]]; then
    checksum=23432b064977908beb1ab4b7f32f024e7331105c875c187dce002aff84b10c11
else
    download "blender-$version.sha256"
    checksum=$(awk -v f="$archive" '$2 == f || $2 == "*" f {print $1}' "$stage/blender-$version.sha256")
fi
[[ $checksum =~ ^[[:xdigit:]]{64}$ ]] || die "No SHA-256 found for $archive"
download "$archive"
(cd -- "$stage" && printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check --status) ||
    die "Blender archive checksum did not match"
mkdir -- "$stage/blender"
tar -xJf "$stage/$archive" -C "$stage/blender" --strip-components=1 --no-same-owner
probe "$stage/blender/blender" || die "Downloaded Blender failed its runtime probe"
if [[ -e $installer_root/blender-$version ]]; then
    backup=$(mktemp -d -- "$installer_root/.previous.XXXXXXXX")
    mv -T -- "$installer_root/blender-$version" "$backup/blender"
fi
mv -T -- "$stage/blender" "$installer_root/blender-$version"
realpath -- "$managed"
