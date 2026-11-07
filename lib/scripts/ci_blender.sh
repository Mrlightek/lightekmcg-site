#!/usr/bin/env bash
set -euo pipefail
# GitHub setup-python adds its shared-library search path to child processes.
# Ubuntu Blender must load Ubuntu's Python and its matching apt-installed NumPy.
STUDIO_SYSTEM_BLENDER_BIN="${STUDIO_SYSTEM_BLENDER_BIN:-/usr/bin/blender}"
exec env -u LD_LIBRARY_PATH -u PYTHONHOME -u PYTHONPATH "$STUDIO_SYSTEM_BLENDER_BIN" "$@"
