#!/usr/bin/env bash
set -euo pipefail
if ! command -v ffmpeg >/dev/null 2>&1; then
  [[ "$EUID" -eq 0 ]] || { echo "Run this script as root on the Ubuntu application server."; exit 1; }
  apt-get update
  apt-get install --no-install-recommends -y ffmpeg
fi
ffmpeg -hide_banner -encoders 2>/dev/null | awk '/libx264/ {v=1} / aac / {a=1} END {if(v&&a) print "LIGHTEK_LIVE_ENCODER_READY"; else exit 1}'
