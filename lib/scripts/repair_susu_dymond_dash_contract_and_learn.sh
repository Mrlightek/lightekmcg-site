#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/susu_dymond_dash_contract_${STAMP}"
mkdir -p "$BACKUP"

CONTROLLERS=(
  "app/controllers/susu_groups_controller.rb"
  "app/controllers/susu_memberships_controller.rb"
  "app/controllers/susu_match_preferences_controller.rb"
)

FILES_TO_BACKUP=(
  "${CONTROLLERS[@]}"
  "app/services/gatekeeper/lesson_service.rb"
  "lib/tasks/gatekeeper_lessons.rake"
  "lib/scripts/gatekeeper/deploy_project.sh"
)

echo "==> Repair Susu / DymondDash controller contract + teach Gatekeeper"
echo "    root: $ROOT"

for f in "${FILES_TO_BACKUP[@]}"; do
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp "$f" "$BACKUP/$f"
  fi
done

# ---------------------------------------------------------------------------
# 1. Correct the controller boundary.
# DymondDash's layout expects account_plan/current_plan_slug/nav_items supplied
# by DymondDash::ApplicationController.
# ---------------------------------------------------------------------------
python3 <<'PY'
from pathlib import Path
import re, sys

files = [
    Path("app/controllers/susu_groups_controller.rb"),
    Path("app/controllers/susu_memberships_controller.rb"),
    Path("app/controllers/susu_match_preferences_controller.rb"),
]

for path in files:
    if not path.exists():
        print(f"ERROR: missing {path}", file=sys.stderr)
        sys.exit(1)

    text = path.read_text()

    old = re.compile(r'^(class\s+\S+\s*<\s*)ApplicationController(\s*)$', re.M)
    if old.search(text):
        text = old.sub(r'\1DymondDash::ApplicationController\2', text, count=1)
        path.write_text(text)
        print(f"UPDATED {path}: now inherits DymondDash::ApplicationController")
    elif "DymondDash::ApplicationController" in text:
        print(f"UNCHANGED {path}: already uses DymondDash::ApplicationController")
    else:
        print(f"ERROR: unexpected superclass in {path}", file=sys.stderr)
        sys.exit(1)
PY

mkdir -p app/services/gatekeeper lib/tasks

# ---------------------------------------------------------------------------
# 2. Generic institutional-memory service.
# This is deliberately reusable for future lessons.
# ---------------------------------------------------------------------------
cat > app/services/gatekeeper/lesson_service.rb <<'RUBY'
module Gatekeeper
  class LessonService
    class KnowledgeBaseUnavailable < StandardError; end

    def self.record!(key:, title:, capability:, symptom:, cause:, remediation:, verification:, metadata: {})
      new(
        key: key,
        title: title,
        capability: capability,
        symptom: symptom,
        cause: cause,
        remediation: remediation,
        verification: verification,
        metadata: metadata
      ).record!
    end

    def initialize(key:, title:, capability:, symptom:, cause:, remediation:, verification:, metadata:)
      @key = key.to_s
      @title = title.to_s
      @capability = capability.to_s
      @symptom = symptom.to_s
      @cause = cause.to_s
      @remediation = remediation.to_s
      @verification = verification.to_s
      @metadata = metadata.to_h
    end

    def record!
      raise KnowledgeBaseUnavailable, "DymondKb::Article is unavailable" unless defined?(DymondKb::Article)
      raise KnowledgeBaseUnavailable, "dymond_kb_articles table is unavailable" unless DymondKb::Article.table_exists?

      article = lookup_article
      attrs = build_attributes(article)
      article.assign_attributes(attrs)
      article.save!

      Rails.logger.info("[Gatekeeper::LessonService] Recorded lesson #{key} as KB article #{article_identifier(article)}")
      article
    end

    private

    attr_reader :key, :title, :capability, :symptom, :cause, :remediation, :verification, :metadata

    def lookup_article
      columns = DymondKb::Article.column_names

      if columns.include?("article_id")
        DymondKb::Article.find_or_initialize_by(article_id: key)
      elsif columns.include?("slug")
        DymondKb::Article.find_or_initialize_by(slug: key)
      else
        DymondKb::Article.find_or_initialize_by(title: title)
      end
    end

    def build_attributes(article)
      columns = article.class.column_names
      attrs = {}

      attrs[:article_id] = key if columns.include?("article_id")
      attrs[:slug] = key.tr("_", "-") if columns.include?("slug")
      attrs[:title] = title if columns.include?("title")
      attrs[:article_type] = "troubleshooting" if columns.include?("article_type")
      attrs[:excerpt] = symptom.first(240) if columns.include?("excerpt")
      attrs[:body] = body if columns.include?("body")
      attrs[:read_minutes] = 3 if columns.include?("read_minutes")
      attrs[:featured] = false if columns.include?("featured")
      attrs[:metadata] = lesson_metadata if columns.include?("metadata")

      attrs
    end

    def body
      <<~TEXT
        ## Symptom

        #{symptom}

        ## Root Cause

        #{cause}

        ## Remediation

        #{remediation}

        ## Verification

        #{verification}

        ## Operational Lesson

        A presentation shell is also a controller contract. When a host application renders a DymondDash layout from a non-DymondDash controller, the controller must inherit from DymondDash::ApplicationController (or otherwise implement the complete contract expected by the layout). Do not copy individual helper methods as a workaround.

        ## Production Diagnostics

        For the Lightek Apache/Passenger deployment, Rails/Passenger request exceptions are available in:
        /var/log/apache2/lightekmcg-site-error.log
      TEXT
    end

    def lesson_metadata
      {
        "source" => "gatekeeper",
        "lesson_key" => key,
        "gatekeeper_capability" => capability,
        "incident_class" => "controller_shell_contract_mismatch",
        "failure_signature" => "NameError: undefined local variable or method `account_plan'",
        "component" => "dymond_dash",
        "affected_feature" => "susu",
        "auto_executable" => false,
        "verification_capability" => "verify_dymond_dash_controller_contract",
        "production_log_path" => "/var/log/apache2/lightekmcg-site-error.log",
        "known_remediation" => "inherit DymondDash::ApplicationController when rendering the DymondDash shell",
        "learned_from_human_intervention" => true
      }.merge(metadata.stringify_keys)
    end

    def article_identifier(article)
      if article.respond_to?(:article_id) && article.article_id.present?
        article.article_id
      elsif article.respond_to?(:slug) && article.slug.present?
        article.slug
      else
        article.id
      end
    end
  end
end
RUBY

# ---------------------------------------------------------------------------
# 3. Idempotent lesson task.
# ---------------------------------------------------------------------------
cat > lib/tasks/gatekeeper_lessons.rake <<'RUBY'
namespace :gatekeeper do
  desc "Record the DymondDash controller-shell contract lesson in the Knowledge Base"
  task learn_dymond_dash_controller_contract: :environment do
    article = Gatekeeper::LessonService.record!(
      key: "GK-LESSON-DYMOND-DASH-CONTROLLER-CONTRACT",
      title: "DymondDash shell requires the DymondDash controller contract",
      capability: "render_dymond_dash_shell",
      symptom: "A host-app page renders with the DymondDash layout but returns HTTP 500. Passenger reports NameError: undefined local variable or method `account_plan` from dymond_dash/shared/_sidebar.html.erb.",
      cause: "The feature controller inherited directly from ApplicationController while rendering dymond_dash/layouts/dymond_dash. The shell expects account_plan, current_plan_slug, nav_items, and related behavior supplied by DymondDash::ApplicationController.",
      remediation: "Make the host feature controller inherit from DymondDash::ApplicationController and preserve its existing routes, actions, callbacks, and business logic. Do not duplicate the DymondDash helper contract into each feature controller.",
      verification: "Run bin/rails zeitwerk:check. Verify SusuGroupsController, SusuMembershipsController, and SusuMatchPreferencesController inherit from DymondDash::ApplicationController. Confirm the controller contract exposes account_plan/current_plan_slug/nav_items. Then request /susu_groups and verify HTTP 200 with the DymondDash sidebar present.",
      metadata: {
        "affected_controllers" => %w[
          SusuGroupsController
          SusuMembershipsController
          SusuMatchPreferencesController
        ],
        "observed_environment" => "production",
        "web_server" => "Apache + Phusion Passenger"
      }
    )

    identifier =
      if article.respond_to?(:article_id) && article.article_id.present?
        article.article_id
      elsif article.respond_to?(:slug) && article.slug.present?
        article.slug
      else
        article.id
      end

    puts "Gatekeeper lesson recorded: #{identifier}"
  rescue Gatekeeper::LessonService::KnowledgeBaseUnavailable => e
    warn "Gatekeeper lesson not persisted yet: #{e.message}"
    warn "The remediation is installed; rerun this task when DymondKb is available."
  end
end
RUBY

# ---------------------------------------------------------------------------
# 4. Make production deployment teach the lesson idempotently.
# Nonfatal because a KB outage must never block application deployment.
# ---------------------------------------------------------------------------
if [[ -f lib/scripts/gatekeeper/deploy_project.sh ]]; then
  python3 <<'PY'
from pathlib import Path

path = Path("lib/scripts/gatekeeper/deploy_project.sh")
src = path.read_text()

marker = "gatekeeper:learn_dymond_dash_controller_contract"

if marker in src:
    print("Deploy script already contains lesson recording hook.")
else:
    anchors = [
        'run_rails "bundle exec rails gatekeeper:dashboard_nav"',
        'run_rails "bundle exec rails db:migrate"',
    ]

    for anchor in anchors:
        if anchor in src:
            addition = (
                anchor
                + '\n\n'
                + 'echo "[knowledge] Record known operational lessons"\n'
                + 'run_rails "bundle exec rails gatekeeper:learn_dymond_dash_controller_contract" || '
                  'echo "[knowledge] Lesson recording skipped; deployment continues"'
            )
            src = src.replace(anchor, addition, 1)
            path.write_text(src)
            print("Added nonfatal Gatekeeper lesson hook to deployment.")
            break
    else:
        print("WARNING: deploy hook anchor not found; run the lesson task manually in production once.")
PY
fi

echo
echo "=== CONTROLLER HEADERS ==="
for f in "${CONTROLLERS[@]}"; do
  echo "--- $f"
  sed -n '1,8p' "$f"
done

echo
echo "=== RUBY SYNTAX ==="
for f in "${CONTROLLERS[@]}"; do ruby -c "$f"; done
ruby -c app/services/gatekeeper/lesson_service.rb
ruby -c lib/tasks/gatekeeper_lessons.rake

echo
echo "=== SHELL SYNTAX ==="
[[ ! -f lib/scripts/gatekeeper/deploy_project.sh ]] || bash -n lib/scripts/gatekeeper/deploy_project.sh

echo
echo "=== ZEITWERK ==="
bin/rails zeitwerk:check

echo
echo "=== CONTROLLER CONTRACT ==="
bin/rails runner '
controllers = [
  SusuGroupsController,
  SusuMembershipsController,
  SusuMatchPreferencesController
]

required = %i[account_plan current_plan_slug nav_items]

controllers.each do |controller|
  inherited = controller.ancestors.include?(DymondDash::ApplicationController)

  available = required.select do |method_name|
    controller.method_defined?(method_name) ||
      controller.private_method_defined?(method_name) ||
      controller.protected_method_defined?(method_name)
  end

  puts "#{controller.name}: dymond_dash=#{inherited} contract=#{available.join(",")}"

  abort "#{controller.name} does not inherit DymondDash::ApplicationController" unless inherited

  missing = required - available
  abort "#{controller.name} missing contract methods: #{missing.join(", ")}" if missing.any?
end
'

echo
echo "=== RECORD LESSON LOCALLY ==="
bin/rails gatekeeper:learn_dymond_dash_controller_contract

echo
echo "=== DIFF CHECK ==="
git diff --check

echo
echo "=== STATUS ==="
git status --short

echo
echo "DONE"
echo "Backup: $BACKUP"
echo
echo "After review:"
echo "  git add -A"
echo "  git commit -m 'Fix Susu DymondDash controller contract and teach Gatekeeper'"
echo "  git push origin main"
