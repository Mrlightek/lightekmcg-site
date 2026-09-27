#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

TARGET_INSTALLER="lib/scripts/install_gatekeeper_provisioning_orchestration_and_health_recovery.sh"
DEPLOY_SCRIPT="lib/scripts/gatekeeper/deploy_project.sh"

[[ -f "$TARGET_INSTALLER" ]] || { echo "ERROR: missing $TARGET_INSTALLER"; exit 1; }
[[ -f "$DEPLOY_SCRIPT" ]] || { echo "ERROR: missing $DEPLOY_SCRIPT"; exit 1; }

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/repair_provisioning_orchestration_${STAMP}"
mkdir -p "$BACKUP/lib/scripts/gatekeeper" "$BACKUP/lib/scripts"

cp "$DEPLOY_SCRIPT" "$BACKUP/$DEPLOY_SCRIPT"
cp "$TARGET_INSTALLER" "$BACKUP/$TARGET_INSTALLER"

echo "==> Repairing Gatekeeper health check using structural detection"

python3 <<'PY'
from pathlib import Path

path = Path("lib/scripts/gatekeeper/deploy_project.sh")
src = path.read_text()

retry_marker = 'Health check attempt ${attempt}/${HEALTH_ATTEMPTS}...'
if retry_marker in src:
    print("Bounded health retry loop already installed.")
    raise SystemExit(0)

lines = src.splitlines(keepends=True)
start = None
end = None

for i, line in enumerate(lines):
    if "HTTP_CODE=" in line and "curl" in line and "${APP_DOMAIN}/up" in line:
        start = i
        break

if start is None:
    for i, line in enumerate(lines):
        if "${APP_DOMAIN}/up" in line:
            nearby = "".join(lines[max(0, i - 6):i + 1])
            if "curl" in nearby:
                for j in range(i, max(-1, i - 8), -1):
                    if "HTTP_CODE=" in lines[j]:
                        start = j
                        break
            if start is not None:
                break

if start is None:
    raise SystemExit("ERROR: could not locate the HTTP_CODE curl health check")

for i in range(start, min(len(lines), start + 16)):
    if "[[" in lines[i] and "HTTP_CODE" in lines[i] and "200" in lines[i]:
        end = i
        break

if end is None:
    for i in range(start, min(len(lines), start + 20)):
        if "healthcheck" in lines[i].lower() and "exit 1" in lines[i]:
            end = i
            break

if end is None:
    context = "".join(lines[max(0, start - 3):min(len(lines), start + 15)])
    raise SystemExit("ERROR: found health curl but not its assertion\n" + context)

replacement = "\n".join([
    'HTTP_CODE=""',
    'HEALTH_URL="https://${APP_DOMAIN}/up"',
    'HEALTH_ATTEMPTS="${GATEKEEPER_HEALTH_ATTEMPTS:-12}"',
    'HEALTH_SLEEP="${GATEKEEPER_HEALTH_SLEEP_SECONDS:-5}"',
    'HEALTH_TIMEOUT="${GATEKEEPER_HEALTH_TIMEOUT_SECONDS:-10}"',
    '',
    'for attempt in $(seq 1 "$HEALTH_ATTEMPTS"); do',
    '  echo "Health check attempt ${attempt}/${HEALTH_ATTEMPTS}..."',
    '',
    '  HTTP_CODE="$(',
    "    curl -L -sS -o /dev/null -w '%{http_code}' \\",
    '      --max-time "$HEALTH_TIMEOUT" \\',
    '      "$HEALTH_URL" || true',
    '  )"',
    '',
    '  if [[ "$HTTP_CODE" == "200" ]]; then',
    '    echo "Health check passed."',
    '    break',
    '  fi',
    '',
    '  echo "Health check returned \'${HTTP_CODE:-no response}\'."',
    '  if [[ "$attempt" -lt "$HEALTH_ATTEMPTS" ]]; then',
    '    sleep "$HEALTH_SLEEP"',
    '  fi',
    'done',
    '',
    '[[ "$HTTP_CODE" == "200" ]] || {',
    '  echo "ERROR: healthcheck failed after ${HEALTH_ATTEMPTS} attempts"',
    '  exit 1',
    '}',
]) + "\n"

new_lines = lines[:start] + [replacement] + lines[end + 1:]
path.write_text("".join(new_lines))
print(f"Replaced health-check block at lines {start + 1}-{end + 1}.")
PY

echo
echo "=== HEALTH BLOCK ==="
grep -n -A35 -B3 'HEALTH_ATTEMPTS=' "$DEPLOY_SCRIPT"

echo
echo "=== SHELL SYNTAX ==="
bash -n "$DEPLOY_SCRIPT"

echo
echo "==> Resuming original provisioning/orchestration installer"
bash "$TARGET_INSTALLER"

echo
echo "=== FINAL HEALTH RETRY VERIFY ==="
grep -n 'Health check attempt' "$DEPLOY_SCRIPT"

echo
echo "=== FINAL DIFF CHECK ==="
git diff --check

echo
echo "REPAIR + COMPLETION SUCCESSFUL"
echo "Backup: $BACKUP"
