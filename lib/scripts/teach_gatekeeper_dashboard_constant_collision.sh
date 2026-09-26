#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

echo "==> Teaching Gatekeeper the Dashboard constant-collision lesson"

bin/rails runner - <<'RUBY'
unless defined?(Gatekeeper::LessonService)
  abort "Gatekeeper::LessonService is not available."
end

article = Gatekeeper::LessonService.record!(
  key: "GK-LESSON-DASHBOARD-CONSTANT-COLLISION",
  title: "Dashboard namespace controllers must preserve the existing Dashboard class",
  capability: "render_dymond_dash_shell",
  symptom: "Rails eager loading fails with TypeError: Dashboard is not a module. The host application already defines Dashboard as an ActiveRecord class.",
  cause: "A nested dashboard controller was declared with `module Dashboard`, which attempts to redefine the existing Dashboard class as a module.",
  remediation: "Preserve the Dashboard ActiveRecord model. Define nested controllers by reopening the existing class namespace directly, for example: `class Dashboard::SusuController < DymondDash::ApplicationController`. Do not wrap the controller in `module Dashboard`.",
  verification: "Confirm `Dashboard < ApplicationRecord` is true, load `Dashboard::SusuController`, and run `bin/rails zeitwerk:check`. The repair is accepted only if all checks pass.",
  metadata: {
    "failure_class" => "TypeError",
    "failure_signature" => "TypeError: Dashboard is not a module",
    "constant" => "Dashboard",
    "bad_pattern" => "module Dashboard",
    "correct_pattern" => "class Dashboard::SusuController < DymondDash::ApplicationController",
    "safe_for_automatic_remediation" => true,
    "verification" => [
      "Dashboard < ApplicationRecord",
      "Dashboard::SusuController loads",
      "bin/rails zeitwerk:check"
    ]
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
puts "Title: #{article.title}"
puts "Failure signature: TypeError: Dashboard is not a module"
puts "Safe auto-remediation: true"
RUBY

echo
echo "=== VERIFY KB ==="
bin/rails runner - <<'RUBY'
article =
  if DymondKb::Article.column_names.include?("article_id")
    DymondKb::Article.find_by(article_id: "GK-LESSON-DASHBOARD-CONSTANT-COLLISION")
  elsif DymondKb::Article.column_names.include?("slug")
    DymondKb::Article.find_by(slug: "gk-lesson-dashboard-constant-collision")
  else
    DymondKb::Article.find_by(title: "Dashboard namespace controllers must preserve the existing Dashboard class")
  end

abort "ERROR: KB article was not found after recording." unless article

puts "Article id:    #{article.id}"
puts "Title:         #{article.title}"
puts "Article type:  #{article.article_type if article.respond_to?(:article_type)}"
puts "Topic:         #{article.topic_id if article.respond_to?(:topic_id)}"
puts "Capability:    #{article.metadata.to_h["gatekeeper_capability"] if article.respond_to?(:metadata)}"
puts "Signature:     #{article.metadata.to_h["failure_signature"] if article.respond_to?(:metadata)}"
RUBY

echo
echo "=== DASHBOARD CONTRACT ==="
bin/rails runner - <<'RUBY'
puts "Dashboard model: #{Dashboard < ApplicationRecord}"
puts "Susu controller: #{Dashboard::SusuController.name}"
puts "Controller parent: #{Dashboard::SusuController.superclass.name}"
RUBY

echo
echo "=== ZEITWERK ==="
bin/rails zeitwerk:check

echo
echo "DONE"
