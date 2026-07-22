#!/bin/bash
set -e
cd ~/Desktop/Development/lightekmcg-site

python3 - << 'PYEOF'
import re
path = "app/models/marlon/ticket_categories.rb"
with open(path) as f:
    content = f.read()

old = '''    def sla_label(id)
      h = ALL.dig(id.to_s, :sla_hours)
      return nil unless h
      h < 24 ? "#{h}h" : "#{h / 24}d"
    end'''
new = '''    def sla_label(id)
      h = ALL.dig(id.to_s, :sla_hours)
      h ? "#{h}h" : nil
    end'''

if old in content:
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("Fixed sla_label — always hours now, matching the real design.")
else:
    print("WARNING: exact text not found, no changes made. Check app/models/marlon/ticket_categories.rb manually.")
PYEOF

echo "Restart:"
echo "  rm -rf tmp/cache/bootsnap*"
echo "  bin/rails server"
