#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

INIT="config/initializers/lightek_dymond_dash_features.rb"
TASK="lib/tasks/gatekeeper_dashboard_nav.rake"
DEPLOY="lib/scripts/gatekeeper/deploy_project.sh"
STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/lightek_dymond_dash_native_features_${STAMP}"

echo "==> Lightek / DymondDash native feature installer"
echo "    root: $ROOT"

mkdir -p "$BACKUP" "$(dirname "$INIT")"

for f in "$INIT" "$TASK" "$DEPLOY"; do
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp "$f" "$BACKUP/$f"
  fi
done

cat > "$INIT" <<'RUBY'
# frozen_string_literal: true

# Host-application features exposed through DymondDash's native FeatureRegistry.
#
# DymondDash builds sidebar navigation from FeatureRegistry.nav_items_for, so
# Gatekeeper and Susu belong here rather than in a second navigation registry.
Rails.application.config.after_initialize do
  next unless defined?(DymondDash::FeatureRegistry)

  DymondDash::FeatureRegistry.register do |f|
    f.slug        = :gatekeeper_infrastructure
    f.label       = "Infrastructure"
    f.icon        = "server"
    f.gem_source  = "lightekmcg-site"
    f.nav_section = :operations
    f.min_plan    = :starter
    f.nav_items   = [
      {
        label: "Infrastructure",
        icon: "server",
        path: "main_app.dashboard_infrastructure_path"
      }
    ]
  end

  DymondDash::FeatureRegistry.register do |f|
    f.slug        = :susu
    f.label       = "Susu"
    f.icon        = "users-group"
    f.gem_source  = "lightekmcg-site"
    f.nav_section = :services
    f.min_plan    = :starter
    f.nav_items   = [
      {
        label: "Susu",
        icon: "users-group",
        path: "main_app.dashboard_susu_path"
      }
    ]
  end
rescue StandardError => e
  Rails.logger.warn "[Lightek/DymondDash] Host feature registration skipped: #{e.class}: #{e.message}"
end
RUBY

# The old task wrote directly to DymondDash navigation tables. The registry now
# owns navigation, so keep the task only as a compatibility/status command.
if [[ -f "$TASK" ]]; then
  cat > "$TASK" <<'RAKE'
# frozen_string_literal: true

namespace :gatekeeper do
  desc "Verify Gatekeeper/Susu DymondDash FeatureRegistry registrations"
  task dashboard_nav: :environment do
    slugs = %i[gatekeeper_infrastructure susu]
    missing = slugs.reject { |slug| DymondDash::FeatureRegistry.find(slug) }

    if missing.any?
      abort "Missing DymondDash feature registrations: #{missing.join(', ')}"
    end

    puts "DymondDash native features registered:"
    slugs.each do |slug|
      feature = DymondDash::FeatureRegistry.find(slug)
      puts "  #{feature.nav_section} -> #{feature.label}"
    end
  end
end
RAKE
fi

echo
echo "==> Ruby syntax"
ruby -c "$INIT"
[[ ! -f "$TASK" ]] || ruby -c "$TASK"

echo
echo "==> Zeitwerk"
bin/rails zeitwerk:check

echo
echo "==> FeatureRegistry verification"
bin/rails runner '
%i[gatekeeper_infrastructure susu].each do |slug|
  feature = DymondDash::FeatureRegistry.find(slug)
  abort "MISSING FEATURE: #{slug}" unless feature
  puts "#{slug}: section=#{feature.nav_section} nav=#{feature.nav_items.inspect}"
end
'

echo
echo "==> Dashboard routes"
bin/rails routes | grep -E 'dashboard_(infrastructure|susu)' || {
  echo "ERROR: expected dashboard routes are missing" >&2
  exit 1
}

if [[ -f "$TASK" ]]; then
  echo
  echo "==> Compatibility task"
  bin/rails gatekeeper:dashboard_nav
fi

echo
echo "==> Diff check"
git diff --check

echo
echo "==> Status"
git status --short

echo
echo "DONE"
echo "Backup: $BACKUP"
echo
echo "Review the diff, then commit/push if it looks right:"
echo "  git diff"
echo "  git add -A"
echo "  git commit -m 'Register Gatekeeper and Susu with DymondDash'"
echo "  git push origin main"
