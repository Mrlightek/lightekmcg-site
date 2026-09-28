#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

CONTROLLER="app/controllers/gatekeeper_controller.rb"
ROUTES="config/routes.rb"

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/remove_gatekeeper_stripe_${STAMP}"

mkdir -p "$BACKUP/app/controllers" "$BACKUP/config"

cp "$CONTROLLER" "$BACKUP/$CONTROLLER"
cp "$ROUTES" "$BACKUP/$ROUTES"

python3 <<'PY'
from pathlib import Path

path = Path("app/controllers/gatekeeper_controller.rb")
lines = path.read_text().splitlines(keepends=True)

start = None
end = None

for i, line in enumerate(lines):
    if line.startswith("  def stripe_webhook"):
        start = i
        break

if start is None:
    print("Gatekeeper stripe_webhook method already absent.")
else:
    for i in range(start + 1, len(lines)):
        if lines[i].startswith("  def ") or lines[i].startswith("  private"):
            end = i
            break

    if end is None:
        raise SystemExit(
            "ERROR: could not safely locate the end of stripe_webhook method."
        )

    del lines[start:end]

    path.write_text("".join(lines))
    print("Removed GatekeeperController#stripe_webhook.")
PY

python3 <<'PY'
from pathlib import Path

path = Path("config/routes.rb")
lines = path.read_text().splitlines(keepends=True)

filtered = []
removed = False

for line in lines:
    if (
        "gatekeeper#stripe_webhook" in line
        or "gatekeeper_stripe_webhook" in line
        or "/gatekeeper/webhooks/stripe" in line
    ):
        print("Removing route:", line.strip())
        removed = True
        continue

    filtered.append(line)

if removed:
    path.write_text("".join(filtered))
else:
    print("Gatekeeper Stripe webhook route already absent.")
PY

echo
echo "=== RUBY SYNTAX ==="
ruby -c "$CONTROLLER"
ruby -c "$ROUTES"

echo
echo "=== ZEITWERK ==="
bin/rails zeitwerk:check

echo
echo "=== STRIPE WEBHOOK ROUTES ==="
bin/rails routes | grep -Ei 'stripe.*webhook|webhooks.*stripe' || true

echo
echo "=== RUNTIME STRIPE SECRET READS ==="
grep -RniE \
  'ENV\[.*STRIPE_(SECRET_KEY|WEBHOOK_SECRET|PUBLISHABLE_KEY)' \
  app \
  || true

echo
echo "=== DIFF CHECK ==="
git diff --check

echo
echo "=== TARGETED DIFF ==="
git --no-pager diff -- \
  "$CONTROLLER" \
  "$ROUTES" \
  Gemfile.lock \
  app/services/dymond_bank/stripe_service.rb \
  lib/tasks/susu_entitlements.rake

echo
echo "=== STATUS ==="
git status --short

echo
echo "DUPLICATE GATEKEEPER STRIPE WEBHOOK REMOVED"
echo "Backup: $BACKUP"
