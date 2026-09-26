#!/usr/bin/env bash
set -euo pipefail

cd "${1:-.}"
[[ -f config/routes.rb ]] || { echo "ERROR: run from Rails app root"; exit 1; }

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/repair_dashboard_routes_${STAMP}"
mkdir -p "$BACKUP"
cp config/routes.rb "$BACKUP/routes.rb"

python3 - config/routes.rb <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
src = path.read_text()

if 'as: :dashboard_infrastructure' in src and 'as: :dashboard_susu' in src:
    print("Dashboard control-plane routes already exist.")
    sys.exit(0)

block = (
    '  # Lightek human control plane\n'
    '  get "/dashboard/infrastructure",\n'
    '      to: "dashboard/infrastructure#index",\n'
    '      as: :dashboard_infrastructure\n\n'
    '  get "/dashboard/susu",\n'
    '      to: "dashboard/susu#index",\n'
    '      as: :dashboard_susu\n\n'
)

insert_at = -1
for token in ("mount DymondDash::Engine", "mount DymondDash"):
    pos = src.find(token)
    if pos >= 0:
        insert_at = src.rfind("\n", 0, pos) + 1
        break

if insert_at >= 0:
    src = src[:insert_at] + block + src[insert_at:]
else:
    needle = "Rails.application.routes.draw do\n"
    if needle not in src:
        raise SystemExit("ERROR: Rails.application.routes.draw do not found")
    src = src.replace(needle, needle + block, 1)

path.write_text(src)
print("Added dashboard infrastructure and Susu host routes.")
PY

echo
echo "=== ROUTE DEFINITIONS ==="
grep -n -A12 -B3 'Lightek human control plane' config/routes.rb

echo
echo "=== RESOLVED ROUTES ==="
bin/rails routes | grep -E 'dashboard_(infrastructure|susu)'

echo
echo "=== ZEITWERK ==="
bin/rails zeitwerk:check

echo
echo "=== DIFF CHECK ==="
git diff --check

echo
echo "ROUTE REPAIR COMPLETE"
echo "Backup: $BACKUP/routes.rb"
echo
echo "Expected URLs:"
echo "  /dashboard/infrastructure"
echo "  /dashboard/susu"
