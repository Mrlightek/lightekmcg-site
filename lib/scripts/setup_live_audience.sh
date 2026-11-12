#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
source_sha=$(cat services/live-audience/Dockerfile services/live-audience/package.json services/live-audience/package-lock.json services/live-audience/bridge.mjs services/live-audience/normalize.mjs | sha256sum | cut -c1-20)
image="lightek/live-audience:$source_sha"
if ! docker image inspect "$image" >/dev/null 2>&1; then
  python3 lib/scripts/deployment_storage.py --app-root "$PWD" \
    --image "$image" --context "$PWD/services/live-audience" --minimum-free-mib 2048
fi
mkdir -p tmp
printf '%s\n' "$image" > tmp/live-audience-image.new
mv tmp/live-audience-image.new tmp/live-audience-image
