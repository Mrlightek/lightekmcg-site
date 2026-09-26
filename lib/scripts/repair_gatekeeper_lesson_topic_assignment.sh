#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

FILE="app/services/gatekeeper/lesson_service.rb"
[[ -f "$FILE" ]] || { echo "ERROR: $FILE not found"; exit 1; }

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/gatekeeper_lesson_topic_fix_${STAMP}"
mkdir -p "$BACKUP/app/services/gatekeeper"
cp "$FILE" "$BACKUP/$FILE"

python3 - "$FILE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
src = path.read_text()

old = '''      article = lookup_article
      attrs = build_attributes(article)
      article.assign_attributes(attrs)
      article.save!
'''

new = '''      article = lookup_article
      attrs = build_attributes(article)
      article.assign_attributes(attrs)
      assign_topic_if_required!(article)
      article.save!
'''

if old in src:
    src = src.replace(old, new, 1)
elif "assign_topic_if_required!(article)" not in src:
    raise SystemExit("ERROR: expected record! block not found")

marker = '''    def build_attributes(article)
'''

method = '''    def assign_topic_if_required!(article)
      return unless article.respond_to?(:topic=)
      return if article.respond_to?(:topic) && article.topic.present?
      return unless defined?(DymondKb::Topic)

      topic = find_existing_topic

      unless topic
        raise KnowledgeBaseUnavailable,
              "DymondKb::Article requires a Topic, but no existing DymondKb::Topic could be selected"
      end

      article.topic = topic
    end

    def find_existing_topic
      scope = DymondKb::Topic.all
      columns = DymondKb::Topic.column_names

      if columns.include?("slug")
        topic = scope.where(slug: %w[troubleshooting operations gatekeeper]).first
        return topic if topic
      end

      %w[name title label].each do |column|
        next unless columns.include?(column)

        topic = scope
          .where("#{column} ILIKE ? OR #{column} ILIKE ? OR #{column} ILIKE ?",
                 "%troubleshoot%", "%operation%", "%gatekeeper%")
          .first
        return topic if topic
      end

      scope.order(:id).first
    end

'''

if "def assign_topic_if_required!" not in src:
    if marker not in src:
        raise SystemExit("ERROR: build_attributes marker not found")
    src = src.replace(marker, method + marker, 1)

path.write_text(src)
print("Patched Gatekeeper::LessonService with required-topic assignment.")
PY

echo
echo "=== RUBY SYNTAX ==="
ruby -c "$FILE"

echo
echo "=== ZEITWERK ==="
bin/rails zeitwerk:check

echo
echo "=== KB TOPIC INVENTORY ==="
bin/rails runner '
if defined?(DymondKb::Topic) && DymondKb::Topic.table_exists?
  puts "Topic columns: #{DymondKb::Topic.column_names.join(", ")}"
  puts "Topic count:   #{DymondKb::Topic.count}"
  DymondKb::Topic.order(:id).limit(10).each do |topic|
    label =
      if topic.respond_to?(:name) && topic.name.present?
        topic.name
      elsif topic.respond_to?(:title) && topic.title.present?
        topic.title
      elsif topic.respond_to?(:label) && topic.label.present?
        topic.label
      elsif topic.respond_to?(:slug) && topic.slug.present?
        topic.slug
      else
        "topic-#{topic.id}"
      end
    puts "  #{topic.id}: #{label}"
  end
else
  puts "DymondKb::Topic unavailable"
end
'

echo
echo "=== RECORD LESSON ==="
bin/rails gatekeeper:learn_dymond_dash_controller_contract

echo
echo "=== VERIFY LESSON ==="
bin/rails runner '
article =
  if DymondKb::Article.column_names.include?("article_id")
    DymondKb::Article.find_by(article_id: "GK-LESSON-DYMOND-DASH-CONTROLLER-CONTRACT")
  elsif DymondKb::Article.column_names.include?("slug")
    DymondKb::Article.find_by(slug: "gk-lesson-dymond-dash-controller-contract")
  else
    DymondKb::Article.find_by(title: "DymondDash shell requires the DymondDash controller contract")
  end

abort "Lesson article was not persisted" unless article

puts "Lesson id:      #{article.id}"
puts "Lesson title:   #{article.title if article.respond_to?(:title)}"
puts "Article type:   #{article.article_type if article.respond_to?(:article_type)}"
puts "Topic:          #{article.topic_id if article.respond_to?(:topic_id)}"
puts "Capability:     #{article.metadata.to_h["gatekeeper_capability"] if article.respond_to?(:metadata)}"
puts "Failure sig:    #{article.metadata.to_h["failure_signature"] if article.respond_to?(:metadata)}"
'

echo
echo "=== DIFF CHECK ==="
git diff --check

echo
echo "=== STATUS ==="
git status --short

echo
echo "DONE"
echo "Backup: $BACKUP"
