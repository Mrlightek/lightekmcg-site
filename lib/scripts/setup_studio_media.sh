#!/usr/bin/env bash
set -euo pipefail
# Run as the same OS account as Sidekiq, from the application checkout.
# Rails stays on Passenger. Blender/FFmpeg are isolated dependency workers.
STUDIO_RUNTIME_IMAGE="${STUDIO_ASSET_WORKER_IMAGE:-lightek/studio-media:20261111}"
STUDIO_RUNTIME_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
command -v docker >/dev/null || { echo 'ERROR: Docker is required for isolated Studio media workers.' >&2; exit 1; }
if ! STUDIO_DOCKER_STATUS="$(docker info 2>&1)"; then
  echo "ERROR: The Studio worker OS account $(id -un) cannot reach its Docker daemon." >&2
  printf '%s\n' "$STUDIO_DOCKER_STATUS" | tail -n 8 >&2
  exit 1
fi
if [[ -z "${STUDIO_ASSET_WORKER_IMAGE:-}" ]]; then
  python3 "$STUDIO_RUNTIME_ROOT/lib/scripts/deployment_storage.py" --app-root "$STUDIO_RUNTIME_ROOT" \
    --image "$STUDIO_RUNTIME_IMAGE" --context "$STUDIO_RUNTIME_ROOT/docker/studio-media" --minimum-free-mib 4096
else
  docker image inspect "$STUDIO_RUNTIME_IMAGE" >/dev/null || docker pull "$STUDIO_RUNTIME_IMAGE"
fi
STUDIO_RUNTIME_CPUS="$(python3 "$STUDIO_RUNTIME_ROOT/lib/scripts/studio_worker_limits.py")"
# Probe with the same restrictions used by imports, without app files/secrets.
docker run --rm --network none --read-only --cap-drop ALL --security-opt no-new-privileges \
  --pids-limit 128 --memory 2g --cpus "$STUDIO_RUNTIME_CPUS" --user "$(id -u):$(id -g)" --tmpfs /tmp:rw,nosuid,size=512m \
  "$STUDIO_RUNTIME_IMAGE" blender --background --factory-startup --disable-autoexec --python-exit-code 1 \
  --python-expr 'import bpy, numpy; assert bpy.app.version >= (4, 0, 0); print("LIGHTEK_BLENDER_RUNTIME_READY=" + bpy.app.version_string)'
if [[ -n "${STUDIO_RENDER_WORKER_IMAGE:-}" && "$STUDIO_RENDER_WORKER_IMAGE" != "$STUDIO_RUNTIME_IMAGE" ]]; then
  docker image inspect "$STUDIO_RENDER_WORKER_IMAGE" >/dev/null || docker pull "$STUDIO_RENDER_WORKER_IMAGE"
fi
if [[ -n "${STUDIO_MEDIA_WORKER_IMAGE:-}" && "$STUDIO_MEDIA_WORKER_IMAGE" != "$STUDIO_RUNTIME_IMAGE" ]]; then
  docker image inspect "$STUDIO_MEDIA_WORKER_IMAGE" >/dev/null || docker pull "$STUDIO_MEDIA_WORKER_IMAGE"
fi
