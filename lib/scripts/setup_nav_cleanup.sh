#!/bin/bash
set -e

# ── 1. New "Team" NavSection, real migration ────────────────────────────────
cd ~/Desktop/Development/dymond_dash
TS=$(date -u +%Y%m%d%H%M%S)
cat > "db/migrate/${TS}_add_team_nav_section.rb" << 'EOF'
# frozen_string_literal: true
class AddTeamNavSection < ActiveRecord::Migration[8.0]
  def up
    return if DymondDash::NavSection.exists?(slug: "team")
    DymondDash::NavSection.create!(label: "Team", slug: "team", position: 1)
    # Shift services/platform/account down to make room, if they're already
    # using position 1/2/3 — safe no-op if they're not.
    DymondDash::NavSection.where(slug: "services").update_all(position: 2)
    DymondDash::NavSection.where(slug: "platform").update_all(position: 3)
    DymondDash::NavSection.where(slug: "account").update_all(position: 4)
  end

  def down
    DymondDash::NavSection.where(slug: "team").destroy_all
  end
end
EOF

echo "── 2. dymond_dash/railtie.rb — split Settings/Appearance out, reassign the rest to :platform ──"
python3 - << 'PYEOF'
path = "lib/dymond_dash/railtie.rb"
with open(path) as f:
    content = f.read()

old_feature = '''      initializer "dymond_dash.register_feature", after: :load_config_initializers do
        DymondDash::FeatureRegistry.register do |f|
          f.slug             = :dymond_dash
          f.label            = "Dashboard & Settings"
          f.icon             = "layout-dashboard"
          f.gem_source       = "dymond_dash"
          f.nav_section      = :account
          f.nav_items        = [
            { label: "Settings",    icon: "settings",  path: "dymond_dash.settings_path"    },
            { label: "Appearance",  icon: "palette",   path: "dymond_dash.appearance_path"  },
            { label: "Marketplace", icon: "package",   path: "dymond_dash.marketplace_path" }
          ]
          f.min_plan = :starter
        end
      rescue StandardError => e
        Rails.logger.warn "[DymondDash] Feature self-registration skipped: #{e.message}"
      end'''

new_feature = '''      # Settings and Appearance moved to the topbar gear dropdown — no longer
      # in the sidebar nav at all. Marketplace stays a real nav destination.
      initializer "dymond_dash.register_feature", after: :load_config_initializers do
        DymondDash::FeatureRegistry.register do |f|
          f.slug             = :dymond_dash
          f.label            = "Marketplace"
          f.icon             = "package"
          f.gem_source       = "dymond_dash"
          f.nav_section      = :platform
          f.nav_items        = [
            { label: "Marketplace", icon: "package", path: "dymond_dash.marketplace_path" }
          ]
          f.min_plan = :starter
        end
      rescue StandardError => e
        Rails.logger.warn "[DymondDash] Feature self-registration skipped: #{e.message}"
      end'''

if old_feature in content:
    content = content.replace(old_feature, new_feature)
    print("  register_feature: OK")
else:
    print("  WARNING: register_feature block not matched exactly — no changes made to that block.")

content = content.replace(
    'f.gem_source  = "dymond_dash"\n        f.nav_section = :overview',
    'f.gem_source  = "dymond_dash"\n        f.nav_section = :platform'
)

with open(path, "w") as f:
    f.write(content)

remaining = content.count("f.nav_section = :overview")
print(f"  remaining :overview registrations in this file (should be 0): {remaining}")
PYEOF

echo ""
echo "── 3. dymond_bank/railtie.rb — :account -> :services ──"
sed -i '' 's/f.nav_section = :account/f.nav_section = :services/' \
  ~/Desktop/Development/dymond_bank/lib/dymond_bank/railtie.rb

echo "── 4. catalog_nav.rb — :overview -> :services ──"
sed -i '' 's/f.gem_source = "catalog"; f.nav_section = :overview/f.gem_source = "catalog"; f.nav_section = :services/' \
  ~/Desktop/Development/lightekmcg-site/config/initializers/catalog_nav.rb

echo "── 5. employee_nav.rb, ticket_nav.rb, employee_users_nav.rb — :overview -> :team ──"
sed -i '' 's/f.gem_source = "host"; f.nav_section = :overview/f.gem_source = "host"; f.nav_section = :team/' \
  ~/Desktop/Development/lightekmcg-site/config/initializers/employee_nav.rb
sed -i '' 's/f.gem_source = "host"; f.nav_section = :overview/f.gem_source = "host"; f.nav_section = :team/' \
  ~/Desktop/Development/lightekmcg-site/config/initializers/ticket_nav.rb
sed -i '' 's/f.gem_source = "host"; f.nav_section = :overview/f.gem_source = "host"; f.nav_section = :team/' \
  ~/Desktop/Development/lightekmcg-site/config/initializers/employee_users_nav.rb

echo "── 6. studio_nav.rb — :overview -> :platform ──"
sed -i '' 's/f.gem_source = "studio"; f.nav_section = :overview/f.gem_source = "studio"; f.nav_section = :platform/' \
  ~/Desktop/Development/lightekmcg-site/config/initializers/studio_nav.rb

echo "── 7. NEW: register Projects + Timesheets (was missing from nav entirely) ──"
cat > ~/Desktop/Development/lightekmcg-site/config/initializers/employee_projects_nav.rb << 'EOF'
# frozen_string_literal: true
# Projects/Timesheets existed with working controllers but no nav entry —
# real gap, fixed here.
Rails.application.config.after_initialize do
  next unless defined?(DymondDash::FeatureRegistry)
  DymondDash::FeatureRegistry.register do |f|
    f.slug = :employee_projects; f.label = "Projects"; f.icon = "briefcase"
    f.gem_source = "host"; f.nav_section = :team; f.min_plan = :starter
    f.nav_items = [
      { label: "Projects",   icon: "briefcase", path: "employee_projects_path" },
      { label: "Timesheets", icon: "clock",     path: "employee_timesheets_path" }
    ]
  end
rescue StandardError => e
  Rails.logger.warn "[Projects] nav registration skipped: #{e.message}"
end
EOF

echo ""
echo "── 8. Sidebar — make sections collapsible via <details>/<summary> ──"
cd ~/Desktop/Development/dymond_dash
python3 - << 'PYEOF'
path = "app/views/dymond_dash/shared/_sidebar.html.erb"
with open(path) as f:
    content = f.read()

old = '''      <% if section %>
        <div class="dd-nav-label"><%= section.label %></div>
      <% end %>

      <% items.each do |item| %>'''

new = '''      <details class="dd-nav-group" open>
        <% if section %>
          <summary class="dd-nav-label"><%= section.label %></summary>
        <% else %>
          <summary class="dd-nav-label" style="list-style:none;"></summary>
        <% end %>

        <% items.each do |item| %>'''

if old in content:
    content = content.replace(old, new)
    print("  sidebar open tag: OK")
else:
    print("  WARNING: sidebar opening block not matched — no changes made.")

# Close the details tag right before the outer grouped.each's end
old_close = '''          <%= dd_badge(badge) if badge.to_i.positive? %>
        <% end %>
      <% end %>
    <% end %>
  </nav>'''

new_close = '''          <%= dd_badge(badge) if badge.to_i.positive? %>
        <% end %>
        <% end %>
      </details>
    <% end %>
  </nav>'''

if old_close in content:
    content = content.replace(old_close, new_close)
    print("  sidebar closing tag: OK")
else:
    print("  WARNING: sidebar closing block not matched — no changes made.")

with open(path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "Adding collapsible CSS (chevron rotation)..."
python3 - << 'PYEOF'
path = "app/views/dymond_dash/layouts/dymond_dash.html.erb"
with open(path) as f:
    content = f.read()

marker = "/* ── Nav ─────────────────────────────────────────────────────────── */"
addition = """/* ── Nav ─────────────────────────────────────────────────────────── */
      .dd-nav-group  { margin-bottom: 2px; }
      .dd-nav-group summary { cursor: pointer; list-style: none; display: flex;
                       align-items: center; justify-content: space-between; }
      .dd-nav-group summary::-webkit-details-marker { display: none; }
      .dd-nav-group summary::after { content: '›'; transform: rotate(90deg);
                       transition: transform 0.15s; color: var(--dd-text-muted); font-size: 11px; }
      .dd-nav-group[open] summary::after { transform: rotate(-90deg); }"""

if marker in content:
    content = content.replace(marker, addition, 1)
    print("  collapsible CSS: OK")
else:
    print("  WARNING: nav CSS marker not found — CSS not added, sections will still work but without chevron styling.")

with open(path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "── 9. Topbar — gear icon dropdown for Settings/Appearance ──"
python3 - << 'PYEOF'
path = "app/views/dymond_dash/layouts/dymond_dash.html.erb"
with open(path) as f:
    content = f.read()

old = '''          <%= yield :topbar_actions %>'''

new = '''          <details class="dd-notif" style="margin-right:2px;">
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
    print("  WARNING: topbar_actions yield marker not found — gear icon not added.")

with open(path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "════════════════════════════════════════════════════════════"
echo "Done. Push THREE gems:"
echo ""
echo "  cd ~/Desktop/Development/dymond_dash"
echo "  git add -A && git commit -m 'Add Team nav section, collapsible sidebar, topbar settings gear' && git push"
echo ""
echo "  cd ~/Desktop/Development/dymond_bank"
echo "  git add -A && git commit -m 'Reassign nav_section to :services' && git push"
echo ""
echo "  cd ~/Desktop/Development/lightekmcg-site"
echo "  bundle update dymond_dash dymond_bank"
echo "  bin/rails db:migrate"
echo "  rm -rf tmp/cache/bootsnap*"
echo "  bin/rails server"
echo ""
echo "NOTE: dymond_studio/lib/dymond_studio/engine.rb line ~46 (f.nav_section = :overview)"
echo "was NOT auto-edited — I haven't seen that file's full content and didn't want to risk"
echo "a wrong match in a gem file blind. Change it to :platform by hand if you want Studio"
echo "grouped with the rest of the site-building tools."
