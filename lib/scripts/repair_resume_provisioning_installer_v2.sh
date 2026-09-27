#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

INSTALLER="lib/scripts/install_gatekeeper_provisioning_orchestration_and_health_recovery.sh"
DEPLOY_SCRIPT="lib/scripts/gatekeeper/deploy_project.sh"

[[ -f "$INSTALLER" ]] || { echo "ERROR: missing $INSTALLER"; exit 1; }
[[ -f "$DEPLOY_SCRIPT" ]] || { echo "ERROR: missing $DEPLOY_SCRIPT"; exit 1; }

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/repair_resume_provisioning_${STAMP}"
mkdir -p "$BACKUP/lib/scripts/gatekeeper" "$BACKUP/lib/scripts"

cp "$INSTALLER" "$BACKUP/$INSTALLER"
cp "$DEPLOY_SCRIPT" "$BACKUP/$DEPLOY_SCRIPT"

echo "==> Confirming deploy health retry is already installed"
grep -q 'Health check attempt ${attempt}/${HEALTH_ATTEMPTS}' "$DEPLOY_SCRIPT" || {
  echo "ERROR: bounded health retry loop is not present in $DEPLOY_SCRIPT"
  exit 1
}

echo "Health retry loop confirmed."

echo
echo "==> Making the installer idempotent for an already-repaired health block"

python3 <<'PY'
from pathlib import Path

path = Path("lib/scripts/install_gatekeeper_provisioning_orchestration_and_health_recovery.sh")
src = path.read_text()

old = '''if new in src:
    print("Health retry loop already installed.")
elif old in src:
    path.write_text(src.replace(old, new, 1))
    print("Replaced single-shot health check with bounded retry loop.")
else:
    raise SystemExit("ERROR: expected Gatekeeper deploy health block not found")
'''

replacement = '''if 'Health check attempt ${attempt}/${HEALTH_ATTEMPTS}...' in src:
    print("Health retry loop already installed.")
elif new in src:
    print("Health retry loop already installed.")
elif old in src:
    path.write_text(src.replace(old, new, 1))
    print("Replaced single-shot health check with bounded retry loop.")
else:
    raise SystemExit("ERROR: expected Gatekeeper deploy health block not found")
'''

if replacement in src:
    print("Installer is already idempotent.")
elif old in src:
    path.write_text(src.replace(old, replacement, 1))
    print("Patched installer to recognize the existing retry loop.")
else:
    raise SystemExit("ERROR: could not locate the installer health-check decision block")
PY

echo
echo "=== INSTALLER SHELL SYNTAX ==="
bash -n "$INSTALLER"

echo
echo "==> Resuming provisioning/orchestration installation"
bash "$INSTALLER"

echo
echo "=== FINAL VERIFY ==="
grep -n 'Health check attempt' "$DEPLOY_SCRIPT"
bin/rails zeitwerk:check
bin/rails routes | grep -E 'dashboard_provisioning_request|validate_dashboard_compute_provider'

echo
echo "=== DIFF CHECK ==="
git diff --check

echo
echo "=== STATUS ==="
git status --short

echo
echo "REPAIR + RESUME COMPLETE"
echo "Backup: $BACKUP"
