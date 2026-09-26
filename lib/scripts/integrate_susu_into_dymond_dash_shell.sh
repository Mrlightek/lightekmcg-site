#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"
STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/susu_dymond_dash_shell_${STAMP}"
mkdir -p "$BACKUP"
CONTROLLERS=("app/controllers/susu_groups_controller.rb" "app/controllers/susu_memberships_controller.rb" "app/controllers/susu_match_preferences_controller.rb")
echo "==> Susu / DymondDash shell integration"
for f in "${CONTROLLERS[@]}"; do
  [[ -f "$f" ]] || { echo "ERROR: missing $f" >&2; exit 1; }
  mkdir -p "$BACKUP/$(dirname "$f")"
  cp "$f" "$BACKUP/$f"
done
python3 <<'PY'
from pathlib import Path
import re, sys
files=[Path("app/controllers/susu_groups_controller.rb"),Path("app/controllers/susu_memberships_controller.rb"),Path("app/controllers/susu_match_preferences_controller.rb")]
for path in files:
    text=path.read_text()
    if 'layout "dymond_dash/layouts/dymond_dash"' in text:
        print("UNCHANGED", path)
        continue
    m=re.search(r'^(class\s+\S+\s*<\s*ApplicationController\s*)$',text,re.M)
    if not m:
        print("ERROR: expected ApplicationController declaration not found:",path,file=sys.stderr); sys.exit(1)
    replacement=m.group(1)+'\n  layout "dymond_dash/layouts/dymond_dash"'
    path.write_text(text[:m.start()]+replacement+text[m.end():])
    print("UPDATED",path)
PY
echo
echo "==> Controller headers"
for f in "${CONTROLLERS[@]}"; do echo "--- $f"; sed -n '1,12p' "$f"; done
echo
echo "==> Ruby syntax"
for f in "${CONTROLLERS[@]}"; do ruby -c "$f"; done
echo
echo "==> Zeitwerk"
bin/rails zeitwerk:check
echo
echo "==> Runtime layout verification"
bin/rails runner '
[SusuGroupsController,SusuMembershipsController,SusuMatchPreferencesController].each do |c|
  puts "#{c.name}: layout=#{c._layout.inspect}"
end
'
echo
echo "==> Diff check"
git diff --check
echo
echo "==> Status"
git status --short
echo
echo "DONE"
echo "Backup: $BACKUP"
echo "Existing Susu routes/controllers/business logic preserved; DymondDash presentation shell added."
