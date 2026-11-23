#!/usr/bin/env bash
set -euo pipefail
# Run as the same OS account as Sidekiq, from the application checkout.
# Rails stays on Passenger. Blender/FFmpeg are isolated dependency workers.
STUDIO_RUNTIME_IMAGE="${STUDIO_ASSET_WORKER_IMAGE:-lightek/studio-media:20261114}"
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
docker run --rm --network none --read-only --cap-drop ALL --security-opt no-new-privileges \
  --pids-limit 128 --memory 256m --cpus "$STUDIO_RUNTIME_CPUS" --user "$(id -u):$(id -g)" \
  "$STUDIO_RUNTIME_IMAGE" node /opt/lightek-editors/movie-render.cjs --health
# Probe under the same host budget and daemon-wide slot used by app jobs.
if BLENDER_MEMORY="$(python3 "$STUDIO_RUNTIME_ROOT/lib/scripts/studio_worker_limits.py" --blender-memory 2g)"; then
  if BLENDER_PROBE="$(docker run --rm --name lightek-blender-slot --network none --read-only --cap-drop ALL --security-opt no-new-privileges \
    --pids-limit 128 --memory "$BLENDER_MEMORY" --memory-swap "$BLENDER_MEMORY" --cpus "$STUDIO_RUNTIME_CPUS" --user "$(id -u):$(id -g)" --tmpfs /tmp:rw,nosuid,size=512m \
    "$STUDIO_RUNTIME_IMAGE" blender --background --factory-startup --disable-autoexec --python-exit-code 1 \
    --python-expr 'import bpy, numpy; assert bpy.app.version >= (4, 4, 0); print("LIGHTEK_BLENDER_RUNTIME_READY=" + bpy.app.version_string)' 2>&1)"; then
    printf '%s\n' "$BLENDER_PROBE"
  else
    probe_status=$?
    if [[ "$probe_status" = 125 && "$BLENDER_PROBE" == *"Conflict."*"lightek-blender-slot"* ]]; then
      echo 'Blender runtime probe deferred because its worker is busy.'
    else
      printf '%s\n' "$BLENDER_PROBE" >&2
      exit "$probe_status"
    fi
  fi
else
  probe_status=$?
  [[ "$probe_status" = 75 ]] || exit "$probe_status"
  echo 'Blender runtime probe deferred by the host memory guard.'
fi
if [[ -n "${STUDIO_RENDER_WORKER_IMAGE:-}" && "$STUDIO_RENDER_WORKER_IMAGE" != "$STUDIO_RUNTIME_IMAGE" ]]; then
  docker image inspect "$STUDIO_RENDER_WORKER_IMAGE" >/dev/null || docker pull "$STUDIO_RENDER_WORKER_IMAGE"
fi
if [[ -n "${STUDIO_MEDIA_WORKER_IMAGE:-}" && "$STUDIO_MEDIA_WORKER_IMAGE" != "$STUDIO_RUNTIME_IMAGE" ]]; then
  docker image inspect "$STUDIO_MEDIA_WORKER_IMAGE" >/dev/null || docker pull "$STUDIO_MEDIA_WORKER_IMAGE"
fi

# Fail deployment clearly if a custom media image lacks the speech engine.
STUDIO_SPEECH_IMAGE="${STUDIO_MEDIA_WORKER_IMAGE:-$STUDIO_RUNTIME_IMAGE}"
docker run --rm --network none --read-only --cap-drop ALL --security-opt no-new-privileges \
  --pids-limit 128 --memory 256m --cpus "$STUDIO_RUNTIME_CPUS" --user "$(id -u):$(id -g)" \
  "$STUDIO_SPEECH_IMAGE" /opt/rhubarb/rhubarb --version

# Exercise the real stdin-to-WAV path offline, under worker restrictions.
printf '%s' 'Nevaeh voice is ready.' | docker run --rm --interactive --network none --read-only --cap-drop ALL --security-opt no-new-privileges \
  --pids-limit 128 --memory 2g --cpus "$STUDIO_RUNTIME_CPUS" --user "$(id -u):$(id -g)" --tmpfs /tmp:rw,nosuid,size=512m \
  --tmpfs /run/lightek-voice:rw,exec,nosuid,nodev,size=16m,mode=1777 --env TMPDIR=/run/lightek-voice \
  "$STUDIO_SPEECH_IMAGE" /opt/lightek-voice/venv/bin/python /opt/lightek-voice/synthesize.py --output /tmp/nevaeh-health.wav

# Contact physics must be installed in the render image before accepting a grasp job.
STUDIO_PHYSICS_IMAGE="${STUDIO_RENDER_WORKER_IMAGE:-$STUDIO_RUNTIME_IMAGE}"
docker run --rm --network none --read-only --cap-drop ALL --security-opt no-new-privileges \
  --pids-limit 128 --memory 256m --cpus "$STUDIO_RUNTIME_CPUS" --user "$(id -u):$(id -g)" \
  --env PYTHONDONTWRITEBYTECODE=1 --env OPENBLAS_NUM_THREADS=1 \
  "$STUDIO_PHYSICS_IMAGE" /opt/lightek-physics/venv/bin/python -c 'import mujoco; assert mujoco.__version__ == "3.3.7"; print("LIGHTEK_CONTACT_PHYSICS_READY=" + mujoco.__version__)'
