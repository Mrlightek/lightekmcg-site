#!/bin/bash
set -euo pipefail
export HOME=/tmp DISPLAY=:99
# Only /work is writable persistent storage. No app files, Vault, host home or
# Docker socket enter this container. Networking is disabled; the host gateway uses a private Unix socket.
Xvfb :99 -screen 0 1600x1000x24 -nolisten tcp -ac &
xvfb_pid=$!
trap 'kill "$xvfb_pid" 2>/dev/null || true' EXIT
for attempt in $(seq 1 50); do xdotool getdisplaygeometry >/dev/null 2>&1 && break; sleep .1; done
openbox --sm-disable >/tmp/openbox.log 2>&1 &
x11vnc -display :99 -localhost -forever -shared -nopw -rfbport 5900 -quiet >/tmp/vnc.log 2>&1 &
python3 /usr/local/bin/lightek-desktop-socket.py >/tmp/websockify.log 2>&1 &
blender --factory-startup --disable-autoexec /work/scene.blend --python /engine/workstation.py
