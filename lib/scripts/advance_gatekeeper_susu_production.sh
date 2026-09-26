#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

[[ -f config/application.rb ]] || {
  echo "ERROR: run from the Rails app root"
  exit 1
}

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/gatekeeper_prod_bootstrap_${STAMP}"
mkdir -p "$BACKUP"

backup() {
  local f="$1"
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp "$f" "$BACKUP/$f"
  fi
}

backup .github/workflows/deploy-production.yml
backup lib/tasks/gatekeeper_infrastructure.rake

mkdir -p lib/tasks

python3 - .github/workflows/deploy-production.yml <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
src = path.read_text()

replacements = {
    "${{ steps.deploy.outputs.sha }}": "${{ steps.deploy.outputs.deployed_sha }}",
    "${{ steps.deploy.outputs.http }}": "${{ steps.deploy.outputs.http_status }}",
}

changed = False
for old, new in replacements.items():
    if old in src:
        src = src.replace(old, new)
        changed = True

if changed:
    path.write_text(src)
    print("Fixed Gatekeeper successful callback output names.")
else:
    print("Callback output names were already correct or expected text was not present.")
PY

cat > lib/tasks/gatekeeper_production_bootstrap.rake <<'RUBY'
namespace :gatekeeper do
  desc "Register/update this Lightek production node and lightekmcg-site project"
  task bootstrap_production: :environment do
    node_name = ENV.fetch("GATEKEEPER_NODE_NAME", "lightekmcg-prod-01")
    node_ip = ENV.fetch("GATEKEEPER_NODE_IP", "127.0.0.1")
    node_hostname = ENV.fetch("GATEKEEPER_NODE_HOSTNAME", "lightekmcg.com")

    node = GatekeeperNode.find_or_initialize_by(name: node_name)
    node.assign_attributes(
      hostname: node_hostname,
      ip_address: node_ip,
      ssh_user: ENV.fetch("GATEKEEPER_NODE_SSH_USER", "root"),
      ssh_port: ENV.fetch("GATEKEEPER_NODE_SSH_PORT", "22").to_i,
      provider: ENV.fetch("GATEKEEPER_NODE_PROVIDER", "Linode"),
      region: ENV["GATEKEEPER_NODE_REGION"],
      status: node.status.presence || "unknown",
      metadata: node.metadata.to_h.merge(
        "role" => "production",
        "managed_by" => "gatekeeper",
        "local_node" => true
      )
    )
    node.save!

    project = GatekeeperProject.find_or_initialize_by(name: "lightekmcg-site")
    project.assign_attributes(
      gatekeeper_node: node,
      repository: ENV.fetch(
        "GATEKEEPER_PROJECT_REPOSITORY",
        "https://github.com/Mrlightek/lightekmcg-site.git"
      ),
      branch: ENV.fetch("GATEKEEPER_PROJECT_BRANCH", "main"),
      domain: ENV.fetch("GATEKEEPER_PROJECT_DOMAIN", "lightekmcg.com"),
      app_root: ENV.fetch("GATEKEEPER_PROJECT_ROOT", "/var/www/lightekmcg-site"),
      app_user: ENV.fetch("GATEKEEPER_PROJECT_USER", "lightek"),
      ruby_version: ENV.fetch("GATEKEEPER_PROJECT_RUBY", "3.3.6"),
      rails_env: "production",
      apache_service_name: ENV.fetch("GATEKEEPER_APACHE_SERVICE", "apache2"),
      sidekiq_service_name: ENV.fetch(
        "GATEKEEPER_SIDEKIQ_SERVICE",
        "lightekmcg-site-sidekiq"
      ),
      status: project.status.presence || "unknown",
      metadata: project.metadata.to_h.merge(
        "health_url" => "https://lightekmcg.com/up",
        "github_repository" => "Mrlightek/lightekmcg-site",
        "github_workflow" => "deploy-production.yml",
        "environment" => "production"
      )
    )
    project.save!

    puts "Gatekeeper production registration complete."
    puts "Node:    #{node.id} #{node.name} (#{node.display_host})"
    puts "Project: #{project.id} #{project.name} (#{project.domain})"
    puts "Status:  node=#{node.status} project=#{project.status}"
  end
end
RUBY

cat > lib/tasks/susu_production_readiness.rake <<'RUBY'
namespace :susu do
  desc "Check Susu production readiness without changing application data"
  task production_readiness: :environment do
    checks = []

    check = lambda do |name, &block|
      begin
        value = block.call
        passed = value != false
        checks << [name, passed, value]
      rescue StandardError => e
        checks << [name, false, "#{e.class}: #{e.message}"]
      end
    end

    check.call("Rails environment") { Rails.env.production? ? "production" : Rails.env }
    check.call("Database") { ActiveRecord::Base.connection.select_value("SELECT 1").to_i == 1 }
    check.call("SusuGroup model") { defined?(SusuGroup) ? "loaded" : false }
    check.call("SusuMembership model") { defined?(SusuMembership) ? "loaded" : false }
    check.call("SusuContribution model") { defined?(SusuContribution) ? "loaded" : false }
    check.call("SusuCycle model") { defined?(SusuCycle) ? "loaded" : false }
    check.call("SusuRound model") { defined?(SusuRound) ? "loaded" : false }
    check.call("SusuCommitment model") { defined?(SusuCommitment) ? "loaded" : false }
    check.call("SusuMatchPreference model") { defined?(SusuMatchPreference) ? "loaded" : false }

    %w[
      susu_groups
      susu_memberships
      susu_contributions
      susu_cycles
      susu_rounds
      susu_commitments
      susu_match_preferences
    ].each do |table|
      check.call("#{table} table") { ActiveRecord::Base.connection.data_source_exists?(table) }
    end

    check.call("Redis") do
      if defined?(Sidekiq)
        Sidekiq.redis { |connection| connection.call("PING") }
      else
        false
      end
    end

    check.call("Susu group routes") do
      helpers = Rails.application.routes.url_helpers
      helpers.respond_to?(:susu_groups_path) ? helpers.susu_groups_path : false
    end

    check.call("Pending migrations") do
      pending = ActiveRecord::MigrationContext
        .new(ActiveRecord::Migrator.migrations_paths)
        .open
        .pending_migrations

      pending.empty? ? "none" : false
    end

    puts
    puts "=== SUSU PRODUCTION READINESS ==="

    checks.each do |name, passed, detail|
      marker = passed ? "PASS" : "FAIL"
      puts format("%-4s  %-30s %s", marker, name, detail.inspect)
    end

    failed = checks.reject { |_name, passed, _detail| passed }

    puts
    puts "Groups:        #{SusuGroup.count if defined?(SusuGroup)}"
    puts "Memberships:   #{SusuMembership.count if defined?(SusuMembership)}"
    puts "Contributions: #{SusuContribution.count if defined?(SusuContribution)}"
    puts "Cycles:        #{SusuCycle.count if defined?(SusuCycle)}"

    puts
    if failed.empty?
      puts "SUSU_READINESS=READY"
    else
      puts "SUSU_READINESS=NOT_READY"
      puts "Failed checks: #{failed.map(&:first).join(', ')}"
      exit 1
    end
  end
end
RUBY

cat > lib/tasks/lightek_production_status.rake <<'RUBY'
namespace :lightek do
  desc "Compact production status for Gatekeeper/Nevaeh"
  task production_status: :environment do
    puts "=== LIGHTEK PRODUCTION STATUS ==="
    puts "Rails:               #{Rails.version}"
    puts "Environment:         #{Rails.env}"
    puts "Gatekeeper nodes:    #{GatekeeperNode.count}"
    puts "Gatekeeper projects: #{GatekeeperProject.count}"
    puts "Operations:          #{GatekeeperOperation.count}"

    gatekeeper_tickets =
      if defined?(Marlon::Ticket)
        Marlon::Ticket.where(related_type: "GatekeeperOperation")
      else
        []
      end

    puts "GK tickets:          #{gatekeeper_tickets.respond_to?(:count) ? gatekeeper_tickets.count : 0}"

    if defined?(SusuGroup)
      puts "Susu groups:         #{SusuGroup.count}"
      puts "Susu memberships:    #{SusuMembership.count}"
      puts "Susu contributions:  #{SusuContribution.count}"
    end
  end
end
RUBY

echo
echo "=== RUBY SYNTAX ==="
ruby -c lib/tasks/gatekeeper_production_bootstrap.rake
ruby -c lib/tasks/susu_production_readiness.rake
ruby -c lib/tasks/lightek_production_status.rake

echo
echo "=== CALLBACK OUTPUTS ==="
grep -nE 'DEPLOYED_SHA:|HTTP_STATUS:' .github/workflows/deploy-production.yml || true

echo
echo "=== DIFF CHECK ==="
git diff --check

echo
echo "Patch installed."
echo "Backup: $BACKUP"
echo
echo "Local checks:"
echo "  bin/rails gatekeeper:bootstrap_production"
echo "  bin/rails lightek:production_status"
echo
echo "Production after push:"
echo "  bin/rails gatekeeper:bootstrap_production"
echo "  bin/rails susu:production_readiness"
echo "  bin/rails gatekeeper:infrastructure_status"
