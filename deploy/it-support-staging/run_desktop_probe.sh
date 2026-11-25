#!/usr/bin/env bash
set -euo pipefail
umask 077

[[ -r "${1:-}" ]] || { echo "Pass a short-lived TURN bundle file." >&2; exit 2; }
bundle=$(realpath "$1")
cd "$(dirname "$0")"
public_dir=$(mktemp -d)
cp desktop.html "$public_dir/index.html"
python3 -m http.server 19084 --bind 127.0.0.1 --directory "$public_dir" >/dev/null 2>&1 &
server=$!
trap 'kill "$server" 2>/dev/null || true; rm -f "$public_dir/index.html"; rmdir "$public_dir"' EXIT
for attempt in {1..30}; do
  if curl --silent --fail http://127.0.0.1:19084/ >/dev/null; then break; fi
  sleep 0.2
done
kill -0 "$server"
xvfb-run -a -s "-screen 0 1280x800x24" node media_probe.cjs "$bundle"
