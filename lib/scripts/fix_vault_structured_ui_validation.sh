#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

INSTALLER="lib/scripts/add_structured_payloads_to_lightek_vault_ui.sh"
CONTROLLER="app/controllers/dashboard/vault_controller.rb"
VIEW="app/views/dashboard/vault/index.html.erb"

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/vault_structured_ui_validation_fix_${STAMP}"

mkdir -p "$BACKUP"

for file in "$INSTALLER" "$CONTROLLER" "$VIEW"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp "$file" "$BACKUP/$file"
  fi
done

echo "==> Removing invalid stdlib ERB validation"

python3 <<'PY'
from pathlib import Path

path = Path("lib/scripts/add_structured_payloads_to_lightek_vault_ui.sh")
src = path.read_text()

old = '''echo
echo "=== ERB SYNTAX ==="
ruby -rerb -e 'RubyVM::InstructionSequence.compile(ERB.new(File.read(ARGV[0])).src)' "$VIEW"
echo "ERB syntax OK"

'''

new = '''echo
echo "=== RAILS VIEW COMPILE ==="
bin/rails runner '
html = ApplicationController.render(
  template: "dashboard/vault/index",
  layout: false,
  assigns: {
    secrets: [],
    audit_events: [],
    active_count: 0,
    expiring_count: 0
  }
)

raise "Vault render returned blank output" if html.blank?
puts "Vault Rails render: PASS"
'

'''

if new in src:
    print("Rails view validation already installed.")
elif old in src:
    path.write_text(src.replace(old, new, 1))
    print("Replaced stdlib ERB validation with Rails rendering.")
else:
    print("WARNING: old ERB validation block not found; installer left unchanged.")
PY

echo
echo "=== CONTROLLER SYNTAX ==="
ruby -c "$CONTROLLER"

echo
echo "=== ZEITWERK ==="
bin/rails zeitwerk:check

echo
echo "=== RAILS VIEW COMPILE ==="
bin/rails runner '
html = ApplicationController.render(
  template: "dashboard/vault/index",
  layout: false,
  assigns: {
    secrets: [],
    audit_events: [],
    active_count: 0,
    expiring_count: 0
  }
)

raise "Vault render returned blank output" if html.blank?
puts "Vault Rails render: PASS"
'

echo
echo "=== DIFF CHECK ==="
git diff --check

echo
echo "=== TARGETED DIFF ==="
git diff -- \
  app/controllers/dashboard/vault_controller.rb \
  app/views/dashboard/vault/index.html.erb \
  lib/scripts/add_structured_payloads_to_lightek_vault_ui.sh

echo
echo "=== STATUS ==="
git status --short

echo
echo "VAULT STRUCTURED UI VALIDATION FIX COMPLETE"
echo "Backup: $BACKUP"
