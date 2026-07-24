#!/bin/bash
set -e
cd ~/Desktop/Development/dymond_dash

echo "Fixing remaining :overview -> :platform (site_editors, templates)..."
sed -i '' 's/f.nav_section = :overview/f.nav_section = :platform/g' lib/dymond_dash/railtie.rb

echo "Fixing register_feature block — label, section, dropping Settings/Appearance nav_items..."
sed -i '' 's/f.label            = "Dashboard & Settings"/f.label            = "Marketplace"/' lib/dymond_dash/railtie.rb
sed -i '' 's/f.nav_section      = :account/f.nav_section      = :platform/' lib/dymond_dash/railtie.rb

python3 - << 'PYEOF'
path = "lib/dymond_dash/railtie.rb"
with open(path) as f:
    content = f.read()

old_items = '''          f.nav_items        = [
            { label: "Settings",    icon: "settings",  path: "dymond_dash.settings_path"    },
            { label: "Appearance",  icon: "palette",   path: "dymond_dash.appearance_path"  },
            { label: "Marketplace", icon: "package",   path: "dymond_dash.marketplace_path" }
          ]'''
new_items = '''          f.nav_items        = [
            { label: "Marketplace", icon: "package", path: "dymond_dash.marketplace_path" }
          ]'''

if old_items in content:
    content = content.replace(old_items, new_items)
    print("  nav_items: OK — Settings/Appearance removed, Marketplace kept")
else:
    print("  WARNING: nav_items block still not matched. Manual fix needed —")
    print("  in lib/dymond_dash/railtie.rb, inside 'dymond_dash.register_feature',")
    print("  remove the Settings and Appearance lines from f.nav_items, keep only Marketplace.")

with open(path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "Verifying no :overview left in this file..."
if grep -q "nav_section.*:overview" lib/dymond_dash/railtie.rb; then
  echo "  WARNING: still present:"
  grep -n "nav_section.*:overview" lib/dymond_dash/railtie.rb
else
  echo "  OK — none left"
fi

echo ""
echo "── Topbar gear icon — using the REAL line (2-space indent, confirmed) ──"
cd ~/Desktop/Development/dymond_dash
python3 - << 'PYEOF'
path = "app/views/dymond_dash/layouts/dymond_dash.html.erb"
with open(path) as f:
    content = f.read()

old = "  <%= yield :topbar_actions %>"
new = '''  <details class="dd-notif" style="margin-right:2px;">
    <summary class="dd-topbar-btn dd-btn-ghost" aria-label="Settings">
      <i class="ti ti-settings"></i>
    </summary>
    <div class="dd-notif-panel" style="width:180px;">
      <%= link_to dymond_dash.settings_path, class: "dd-notif-item" do %>
        <i class="ti ti-settings"></i> Settings
      <% end %>
      <%= link_to dymond_dash.appearance_path, class: "dd-notif-item" do %>
        <i class="ti ti-palette"></i> Appearance
      <% end %>
    </div>
  </details>
  <%= yield :topbar_actions %>'''

if old in content:
    content = content.replace(old, new, 1)
    print("  topbar gear dropdown: OK")
else:
    print("  WARNING: still not matched — paste back 'grep -n \"topbar_actions\"' output again.")

with open(path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "Done. Push:"
echo "  cd ~/Desktop/Development/dymond_dash"
echo "  git add -A && git commit -m 'Fix remaining nav_section reassignments and topbar gear icon'"
echo "  git push"
echo ""
echo "  cd ~/Desktop/Development/lightekmcg-site"
echo "  bundle update dymond_dash"
echo "  rm -rf tmp/cache/bootsnap*"
echo "  bin/rails server"
