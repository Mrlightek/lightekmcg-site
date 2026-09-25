#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

[[ -f config/application.rb ]] || { echo "ERROR: run from Rails app root"; exit 1; }
[[ -f app/models/gatekeeper_operation.rb ]] || { echo "ERROR: Gatekeeper foundation is not installed"; exit 1; }

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/gatekeeper_support_kb_backup_${STAMP}"
mkdir -p "$BACKUP"

backup() {
  local f="$1"
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp "$f" "$BACKUP/$f"
  fi
}

for f in \
  app/models/gatekeeper_operation.rb \
  app/models/gatekeeper_escalation.rb \
  app/services/gatekeeper/executor.rb \
  app/services/gatekeeper/metrics.rb \
  app/controllers/gatekeeper/infrastructure_controller.rb \
  app/views/gatekeeper/infrastructure/index.html.erb \
  app/models/dymond_kb/article.rb \
  app/controllers/dymond_kb/kb_dashboard_controller.rb
  do backup "$f"; done

mkdir -p app/services/gatekeeper

MIGRATION="$(find db/migrate -maxdepth 1 -type f -name '*integrate_gatekeeper_with_kb_and_tickets*.rb' | head -1 || true)"
if [[ -z "$MIGRATION" ]]; then
  MIGRATION="db/migrate/$(date +%Y%m%d%H%M%S)_integrate_gatekeeper_with_kb_and_tickets.rb"
  cat > "$MIGRATION" <<'RUBY'
class IntegrateGatekeeperWithKbAndTickets < ActiveRecord::Migration[8.0]
  def up
    unless column_exists?(:dymond_kb_articles, :metadata)
      add_column :dymond_kb_articles, :metadata, :jsonb, null: false, default: {}
      add_index :dymond_kb_articles, :metadata, using: :gin
    end

    drop_table :gatekeeper_escalations, if_exists: true
  end

  def down
    unless table_exists?(:gatekeeper_escalations)
      create_table :gatekeeper_escalations do |t|
        t.references :gatekeeper_operation, null: false, foreign_key: true
        t.string :category, null: false, default: "unknown_condition"
        t.string :status, null: false, default: "open"
        t.text :reason, null: false
        t.text :resolution
        t.boolean :capability_created, null: false, default: false
        t.datetime :resolved_at
        t.timestamps
      end
      add_index :gatekeeper_escalations, :status
      add_index :gatekeeper_escalations, :category
    end

    remove_index :dymond_kb_articles, :metadata if index_exists?(:dymond_kb_articles, :metadata)
    remove_column :dymond_kb_articles, :metadata if column_exists?(:dymond_kb_articles, :metadata)
  end
end
RUBY
fi

cat > app/models/gatekeeper_operation.rb <<'RUBY'
class GatekeeperOperation < ApplicationRecord
  STATUSES = %w[queued running succeeded failed].freeze

  belongs_to :gatekeeper_node
  belongs_to :gatekeeper_project, optional: true

  has_one :support_ticket,
          -> { where(related_type: "GatekeeperOperation") },
          class_name: "Marlon::Ticket",
          foreign_key: :related_id,
          dependent: :nullify,
          inverse_of: false

  validates :capability, :requested_by, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :recent_first, -> { order(created_at: :desc) }
  scope :failed, -> { where(status: "failed") }

  def ticketed?
    support_ticket.present?
  end
end
RUBY

rm -f app/models/gatekeeper_escalation.rb

cat > app/services/gatekeeper/knowledge_service.rb <<'RUBY'
module Gatekeeper
  class KnowledgeService
    MAX_MATCHES = 5

    def self.for_capability(capability)
      return DymondKb::Article.none unless DymondKb::Article.table_exists?

      DymondKb::Article
        .where(article_type: "troubleshooting")
        .where("metadata ->> 'gatekeeper_capability' = ?", capability.to_s)
        .ordered
    end

    def self.find_for_failure(operation:, error:)
      direct = for_capability(operation.capability).to_a
      return direct.first(MAX_MATCHES) if direct.any?

      query = [operation.capability.to_s.tr("_", " "), error&.message.to_s]
        .reject(&:blank?)
        .join(" ")
        .squish
        .first(240)

      return [] if query.blank?

      DymondKb::Article
        .where(article_type: "troubleshooting")
        .search(query)
        .ordered
        .limit(MAX_MATCHES)
        .to_a
    rescue StandardError => e
      Rails.logger.warn("[Gatekeeper::KnowledgeService] KB lookup failed: #{e.class}: #{e.message}")
      []
    end
  end
end
RUBY

cat > app/services/gatekeeper/support_ticket_service.rb <<'RUBY'
require "securerandom"

module Gatekeeper
  class SupportTicketService
    def self.open_for_failure!(operation:, error:, knowledge_articles: [])
      existing = Marlon::Ticket.find_by(
        related_type: "GatekeeperOperation",
        related_id: operation.id
      )
      return existing if existing

      ticket = Marlon::Ticket.new(
        category: "technical",
        title: "Gatekeeper: #{operation.capability.humanize} failed",
        description: description_for(operation, error),
        priority: "high",
        urgency: 8,
        status: "open",
        organization_name: "Lightek MCG",
        assigned_team: "Technical",
        assigned_rep: "Nevaeh / Gatekeeper",
        related_type: "GatekeeperOperation",
        related_id: operation.id,
        extra_fields: extra_fields_for(operation, error, knowledge_articles)
      )

      save_with_number_fallback!(ticket)

      record_event!(
        ticket,
        action: "gatekeeper_escalated",
        detail: "Gatekeeper exhausted the currently known execution path for #{operation.capability}."
      )

      if knowledge_articles.any?
        record_event!(
          ticket,
          action: "kb_consulted",
          detail: "Knowledge consulted: #{knowledge_articles.map(&:article_id).join(', ')}"
        )
      end

      ticket
    end

    def self.record_event!(ticket, action:, detail:, actor_id: nil)
      Marlon::TicketEvent.create!(
        ticket_id: ticket.id,
        actor_id: actor_id,
        action: action,
        detail: detail
      )
    rescue StandardError => e
      Rails.logger.warn("[Gatekeeper::SupportTicketService] Ticket event failed: #{e.class}: #{e.message}")
      nil
    end

    def self.description_for(operation, error)
      <<~TEXT
        Gatekeeper could not complete an automated operation.

        Capability: #{operation.capability}
        Node: #{operation.gatekeeper_node&.name}
        Project: #{operation.gatekeeper_project&.name || "N/A"}
        Requested by: #{operation.requested_by}
        Error: #{error.class}: #{error.message}

        This ticket was created automatically because the known Gatekeeper execution path did not complete successfully.
      TEXT
    end
    private_class_method :description_for

    def self.extra_fields_for(operation, error, knowledge_articles)
      {
        "source" => "gatekeeper",
        "gatekeeper" => {
          "operation_id" => operation.id,
          "capability" => operation.capability,
          "node_id" => operation.gatekeeper_node_id,
          "project_id" => operation.gatekeeper_project_id,
          "exit_status" => operation.exit_status,
          "error_class" => error.class.name,
          "error_message" => error.message,
          "requested_by" => operation.requested_by,
          "kb_articles_consulted" => knowledge_articles.map(&:article_id),
          "known_recovery_exhausted" => true
        }
      }
    end
    private_class_method :extra_fields_for

    def self.save_with_number_fallback!(ticket)
      ticket.save!
    rescue ActiveRecord::RecordInvalid
      raise unless ticket.errors[:number].present?

      ticket.number ||= "LT-GK-#{Time.current.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(2).upcase}"
      ticket.save!
    end
    private_class_method :save_with_number_fallback!
  end
end
RUBY

cat > app/services/gatekeeper/executor.rb <<'RUBY'
module Gatekeeper
  class Executor
    def self.call(capability:, node:, project: nil, requested_by:, parameters: {})
      operation = nil
      capability_name = capability.to_s
      capability_class = CapabilityRegistry.fetch!(capability_name)

      operation = GatekeeperOperation.create!(
        gatekeeper_node: node,
        gatekeeper_project: project,
        capability: capability_name,
        requested_by: requested_by.to_s,
        parameters: parameters.to_h,
        status: "running",
        started_at: Time.current
      )

      result = capability_class.call(node:, project:, parameters: parameters.to_h)

      operation.update!(
        status: "succeeded",
        command: result[:command],
        output: result[:output],
        exit_status: result[:exit_status],
        result: result.except(:command, :output, :exit_status),
        completed_at: Time.current
      )

      operation
    rescue StandardError => e
      if operation
        operation.update!(
          status: "failed",
          error_class: e.class.name,
          error_message: e.message,
          completed_at: Time.current
        )

        knowledge = KnowledgeService.find_for_failure(operation:, error: e)
        ticket = SupportTicketService.open_for_failure!(
          operation: operation,
          error: e,
          knowledge_articles: knowledge
        )

        operation.update!(
          result: operation.result.to_h.merge(
            "support_ticket_id" => ticket.id,
            "support_ticket_number" => ticket.number,
            "kb_article_ids" => knowledge.map(&:article_id)
          )
        )
      end

      raise
    end
  end
end
RUBY

cat > app/services/gatekeeper/metrics.rb <<'RUBY'
module Gatekeeper
  class Metrics
    def self.summary(since: 7.days.ago)
      operations = GatekeeperOperation.where(created_at: since..)

      tickets = Marlon::Ticket.where(
        related_type: "GatekeeperOperation",
        created_at: since..
      )

      open_tickets = Marlon::Ticket
        .where(related_type: "GatekeeperOperation")
        .where.not(status: "resolved")

      total = operations.count
      interventions = tickets.count

      {
        operations: total,
        succeeded: operations.where(status: "succeeded").count,
        failed: operations.where(status: "failed").count,
        support_tickets: tickets.count,
        open_support_tickets: open_tickets.count,
        human_interventions: interventions,
        marlon_dependency_rate: total.zero? ? 0.0 : interventions.to_f / total
      }
    end
  end
end
RUBY

cat > app/controllers/gatekeeper/infrastructure_controller.rb <<'RUBY'
module Gatekeeper
  class InfrastructureController < ApplicationController
    def index
      @nodes = GatekeeperNode.includes(:gatekeeper_projects).order(:name)
      @operations = GatekeeperOperation.includes(:gatekeeper_node, :gatekeeper_project).recent_first.limit(20)
      @support_tickets = Marlon::Ticket
        .where(related_type: "GatekeeperOperation")
        .where.not(status: "resolved")
        .order(created_at: :desc)
        .limit(20)
      @metrics = Metrics.summary
    end
  end
end
RUBY

cat > app/views/gatekeeper/infrastructure/index.html.erb <<'ERB'
<% content_for :title, "Gatekeeper Infrastructure" %>
<section style="max-width:1200px;margin:0 auto;padding:32px 20px;">
  <p>GATEKEEPER</p>
  <h1>Infrastructure Control</h1>
  <p>Nevaeh decides. Gatekeeper executes. Marlon handles the unknown.</p>

  <p>
    <%= link_to "Nodes", gatekeeper_nodes_path %> ·
    <%= link_to "Projects", gatekeeper_projects_path %> ·
    <%= link_to "Add Node", new_gatekeeper_node_path %> ·
    <%= link_to "Add Project", new_gatekeeper_project_path %>
  </p>

  <h2>Marlon Dependency</h2>
  <ul>
    <li>Operations: <%= @metrics[:operations] %></li>
    <li>Succeeded: <%= @metrics[:succeeded] %></li>
    <li>Failed: <%= @metrics[:failed] %></li>
    <li>Support tickets: <%= @metrics[:support_tickets] %></li>
    <li>Need intervention: <%= @metrics[:open_support_tickets] %></li>
    <li>Dependency rate: <%= number_to_percentage(@metrics[:marlon_dependency_rate] * 100, precision: 2) %></li>
  </ul>

  <h2>Nodes</h2>
  <% @nodes.each do |node| %>
    <p><%= link_to node.name, gatekeeper_node_path(node) %> — <%= node.status %> — <%= node.display_host %></p>
  <% end %>

  <h2>Gatekeeper Trouble Tickets</h2>
  <% if @support_tickets.any? %>
    <% @support_tickets.each do |ticket| %>
      <p>
        <strong><%= ticket.number %></strong> — <%= ticket.status %> — <%= ticket.title %>
        — <%= link_to "Open", employee_ticket_path(ticket) %>
      </p>
    <% end %>
  <% else %>
    <p>Nothing requires your attention.</p>
  <% end %>

  <h2>Recent Operations</h2>
  <% @operations.each do |operation| %>
    <p>
      <%= operation.capability %> — <%= operation.status %> — <%= operation.requested_by %>
      <% if operation.result.to_h["support_ticket_number"].present? %>
        — Ticket <%= operation.result["support_ticket_number"] %>
      <% end %>
    </p>
  <% end %>
</section>
ERB

ARTICLE_MODEL=""
for f in app/models/dymond_kb/article.rb app/models/article.rb; do
  [[ -f "$f" ]] && ARTICLE_MODEL="$f" && break
done

if [[ -n "$ARTICLE_MODEL" ]]; then
  python3 - "$ARTICLE_MODEL" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text()
if 'scope :troubleshooting' not in s:
    s = s.replace(
        '    scope :featured, -> { where(featured: true) }\n',
        '    scope :featured, -> { where(featured: true) }\n'
        '    scope :troubleshooting, -> { where(article_type: "troubleshooting") }\n'
        '    scope :for_gatekeeper_capability, ->(capability) {\n'
        '      troubleshooting.where("metadata ->> \'gatekeeper_capability\' = ?", capability.to_s)\n'
        '    }\n',
        1
    )
if 'def gatekeeper_capability' not in s:
    s = s.replace(
        '    def type_label\n',
        '    def gatekeeper_capability\n'
        '      metadata.to_h["gatekeeper_capability"].presence\n'
        '    end\n\n'
        '    def gatekeeper_auto_executable?\n'
        '      ActiveModel::Type::Boolean.new.cast(metadata.to_h["auto_executable"])\n'
        '    end\n\n'
        '    def gatekeeper_verification_capability\n'
        '      metadata.to_h["verification_capability"].presence\n'
        '    end\n\n'
        '    def type_label\n',
        1
    )
p.write_text(s)
print(f"Patched {p}")
PY
else
  echo "WARNING: DymondKb::Article model is supplied by a gem/engine and was not found in app/models."
  echo "         The DB metadata column will still be created; patch the engine model in its repo too."
fi

KB_DASH=""
for f in app/controllers/dymond_kb/kb_dashboard_controller.rb app/controllers/kb_dashboard_controller.rb; do
  [[ -f "$f" ]] && KB_DASH="$f" && break
done

if [[ -n "$KB_DASH" ]]; then
  python3 - "$KB_DASH" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text()
old = ':excerpt, :body, :read_minutes, :featured, :sort_order)'
new = ':excerpt, :body, :read_minutes, :featured, :sort_order, metadata: {})'
if old in s:
    s = s.replace(old, new, 1)
    p.write_text(s)
    print(f"Patched {p}")
else:
    print(f"WARNING: article_params shape not found in {p}; metadata permit unchanged.")
PY
fi

cat > lib/tasks/gatekeeper_infrastructure.rake <<'RUBY'
namespace :gatekeeper do
  desc "Show Gatekeeper infrastructure, trouble-ticket, and Marlon dependency status"
  task infrastructure_status: :environment do
    metrics = Gatekeeper::Metrics.summary

    puts "Nodes:                 #{GatekeeperNode.count}"
    puts "Projects:              #{GatekeeperProject.count}"
    puts "Operations:            #{metrics[:operations]}"
    puts "Succeeded:             #{metrics[:succeeded]}"
    puts "Failed:                #{metrics[:failed]}"
    puts "Support tickets:       #{metrics[:support_tickets]}"
    puts "Need intervention:     #{metrics[:open_support_tickets]}"
    puts "Human interventions:   #{metrics[:human_interventions]}"
    puts format("Marlon dependency:    %.2f%%", metrics[:marlon_dependency_rate] * 100)
  end
end
RUBY

echo
echo "=== Syntax checks ==="
ruby -c app/models/gatekeeper_operation.rb
ruby -c app/services/gatekeeper/knowledge_service.rb
ruby -c app/services/gatekeeper/support_ticket_service.rb
ruby -c app/services/gatekeeper/executor.rb
ruby -c app/services/gatekeeper/metrics.rb
ruby -c app/controllers/gatekeeper/infrastructure_controller.rb
ruby -c "$MIGRATION"
[[ -n "$ARTICLE_MODEL" ]] && ruby -c "$ARTICLE_MODEL"
[[ -n "$KB_DASH" ]] && ruby -c "$KB_DASH"

git diff --check

echo
echo "Gatekeeper -> KB -> Marlon Ticket integration installed."
echo "Backup: $BACKUP"
echo "Migration: $MIGRATION"
echo
echo "Next:"
echo "  bin/rails db:migrate"
echo "  bin/rails gatekeeper:infrastructure_status"
echo "  bin/rails runner 'puts DymondKb::Article.column_names.include?(\"metadata\")'"
