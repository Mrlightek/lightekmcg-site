#!/usr/bin/env bash
set -euo pipefail

cd "${1:-.}"
[[ -f config/application.rb ]] || { echo "ERROR: run from Rails app root"; exit 1; }

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/repair_dashboard_controller_namespace_${STAMP}"
mkdir -p "$BACKUP"

FILES=(
  app/controllers/dashboard/infrastructure_controller.rb
  app/controllers/dashboard/susu_controller.rb
)

for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || { echo "ERROR: expected controller not found: $f"; exit 1; }
  mkdir -p "$BACKUP/$(dirname "$f")"
  cp "$f" "$BACKUP/$f"
done

python3 - <<'PY'
from pathlib import Path

files = [
    Path("app/controllers/dashboard/infrastructure_controller.rb"),
    Path("app/controllers/dashboard/susu_controller.rb"),
]

for path in files:
    text = path.read_text()

    if text.startswith("module Dashboard\n"):
        text = text.replace("module Dashboard\n", "class Dashboard\n", 1)
    elif text.startswith("class Dashboard\n"):
        pass
    else:
        raise SystemExit(f"ERROR: unexpected namespace header in {path}")

    path.write_text(text)
    print(f"Repaired {path}")
PY

echo
echo "=== RUBY SYNTAX ==="
ruby -c app/controllers/dashboard/infrastructure_controller.rb
ruby -c app/controllers/dashboard/susu_controller.rb

echo
echo "=== ZEITWERK ==="
bin/rails zeitwerk:check

echo
echo "=== ROUTES ==="
bin/rails routes | grep -E 'dashboard_(infrastructure|susu)' || true

echo
echo "=== DIFF CHECK ==="
git diff --check

echo
echo "REPAIR COMPLETE"
echo "Backup: $BACKUP"
echo
echo "Dashboard remains your existing ActiveRecord model/class."
echo "The nested controllers are now valid constants:"
echo "  Dashboard::InfrastructureController"
echo "  Dashboard::SusuController"
