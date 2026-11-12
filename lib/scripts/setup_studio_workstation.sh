#!/usr/bin/env bash
set -euo pipefail
# Application account step; service and Apache configuration are installed by
# install_studio_workstation.py from the root deployment/update pipeline.
STUDIO_WORKSTATION_CHECKOUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STUDIO_WORKSTATION_STATE="${STUDIO_WORKSTATION_ROOT:-${STUDIO_WORKSTATION_CHECKOUT}/storage/studio-workstations}"
STUDIO_WORKSTATION_IMAGE_NAME="${STUDIO_WORKSTATION_IMAGE:-lightek/studio-workstation:20261107}"
command -v docker >/dev/null || { echo 'Docker is required for native workstations.' >&2; exit 1; }
docker info >/dev/null
if [[ -z "${STUDIO_WORKSTATION_IMAGE:-}" ]]; then
  python3 "$STUDIO_WORKSTATION_CHECKOUT/lib/scripts/deployment_storage.py" --app-root "$STUDIO_WORKSTATION_CHECKOUT" \
    --image "$STUDIO_WORKSTATION_IMAGE_NAME" --context "$STUDIO_WORKSTATION_CHECKOUT/docker/studio-workstation" --minimum-free-mib 4096
else
  docker image inspect "$STUDIO_WORKSTATION_IMAGE_NAME" >/dev/null || docker pull "$STUDIO_WORKSTATION_IMAGE_NAME"
fi
mkdir -p "$STUDIO_WORKSTATION_STATE/sessions"
chmod 700 "$STUDIO_WORKSTATION_STATE" "$STUDIO_WORKSTATION_STATE/sessions"
python3 - "$STUDIO_WORKSTATION_STATE/gateway.key" <<'PY'
import os,secrets,sys
try:
    fd=os.open(sys.argv[1],os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
except FileExistsError:
    if os.path.islink(sys.argv[1]) or os.path.getsize(sys.argv[1])<32: raise SystemExit('Invalid workstation gateway key')
else:
    with os.fdopen(fd,'wb') as output: output.write(secrets.token_bytes(64))
PY
# noVNC HTML/JS is host-owned trusted content, not served from an editable guest.
STUDIO_ASSET_CONTAINER="$(docker create "$STUDIO_WORKSTATION_IMAGE_NAME")"
trap 'docker rm -f "$STUDIO_ASSET_CONTAINER" >/dev/null 2>&1 || true' EXIT
mkdir -p "$STUDIO_WORKSTATION_STATE/novnc"
docker cp "$STUDIO_ASSET_CONTAINER:/usr/share/novnc/." "$STUDIO_WORKSTATION_STATE/novnc/"
echo 'STUDIO_WORKSTATION_DEPENDENCIES_READY=1'
