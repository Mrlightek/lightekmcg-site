# frozen_string_literal: true

# Controlled persistence integration. Runs without the host's private Rails
# engines: ruby test/standalone/nevaeh_backlog_test.rb
# SQLite/ActiveRecord + ActiveJob exercise real app code, not production acceptance.
require "minitest/autorun"
require "active_record"
require "active_job"
require "active_support/all"
require "tmpdir"
require "logger"
require "securerandom"

ROOT = File.expand_path("../..", __dir__)
DATABASE = File.join(Dir.tmpdir, "nevaeh-backlog-#{Process.pid}.sqlite3")
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: DATABASE)
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table(:users) { |t| t.string :role }
  create_table :marlon_tickets do |t|
    %i[number title category priority status assigned_team assigned_rep description related_type].each { |c| t.string c }
    t.integer :urgency
    t.integer :submitted_by_id
    t.integer :related_id
    t.json :extra_fields
    t.datetime :resolved_at
    t.timestamps
  end
  create_table :marlon_ticket_events do |t|
    t.integer :ticket_id
    t.integer :actor_id
    t.string :action
    t.text :detail
    t.timestamps
  end
  create_table :nevaeh_capabilities do |t|
    %i[name slug domain intent_name handler queue gatekeeper_capability].each { |c| t.string c }
    t.integer :priority
    t.boolean :enabled
    t.timestamps
  end
  create_table :gatekeeper_operations do |t|
    t.string :capability
    t.string :status
    t.json :result
  end
  create_table :dymond_dispatch_work_items do |t|
    t.string :kind
    t.string :handler
    t.string :status
    t.string :correlation_id
    t.string :subject_type
    t.integer :subject_id
    t.json :result
    t.text :error
  end
  create_table(:studio_projects) { |t| t.string :name }
  create_table(:productions) { |t| t.integer :studio_project_id }
  create_table(:studio_scenes) { |t| t.integer :studio_project_id; t.integer :production_id }
  create_table :dymond_kb_articles do |t|
    %i[title article_id slug article_type excerpt].each { |c| t.string c }
    t.text :body
    t.json :metadata
    t.timestamps
  end
end
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end
class ApplicationJob < ActiveJob::Base; end
# Minimal host adapters. Real ticket models/services/jobs below are loaded intact.
class User < ApplicationRecord
  def employee? = %w[employee admin super_admin].include?(role)
end
class Ability
  def initialize(user) = @user = user
  def can?(*args) = %w[admin super_admin].include?(@user.role)
end
module Rails
  def self.env = (@env ||= ActiveSupport::StringInquirer.new("test"))
  def self.env=(value)
    @env = ActiveSupport::StringInquirer.new(value)
  end
  def self.logger = (@logger ||= Logger.new(File::NULL))
end
module DymondKb
  class Article < ApplicationRecord
    self.table_name = "dymond_kb_articles"
    scope :ordered, -> { order(:id) }
    def self.search(query) = where("title LIKE ?", "%#{sanitize_sql_like(query)}%")
  end
end
module DymondDispatch
  class WorkItem < ApplicationRecord
    self.table_name = "dymond_dispatch_work_items"
  end
end
class GatekeeperOperation < ApplicationRecord; end
class StudioProject < ApplicationRecord; end
class Production < ApplicationRecord; end
class StudioScene < ApplicationRecord; end
module NevaehOrchestration
  # SQLite has no PostgreSQL metadata operator. Only the engine's read adapter
  # is substituted; results below are persisted real KB rows, never canned matches.
  class KnowledgeResolver
    def self.for(capability:, additional_article_ids: [])
      DymondKb::Article.all.select do |a|
        a.metadata.to_h.values_at("capability", "nevaeh_capability").include?(capability) ||
          additional_article_ids.map(&:to_s).include?(a.article_id.to_s)
      end.first(5)
    end
  end
end
%w[models/marlon/ticket_categories models/marlon/ticket_event models/marlon/ticket models/nevaeh_capability
   services/nevaeh_intelligences/work_order services/nevaeh_intelligences/ticket_approval
   services/nevaeh_intelligences/dispatch services/nevaeh_intelligences/ticket_execution
   services/nevaeh_intelligences/studio_capability_plan_resolution_v7a
   services/nevaeh_intelligences/github_development_plan_v7a services/nevaeh_intelligences/ticket_backlog
   jobs/nevaeh_intelligences/process_backlog_job services/gatekeeper/lesson_service].each do |file|
  require File.join(ROOT, "app", "#{file}.rb")
end
ActiveJob::Base.queue_adapter = :test
ActiveJob::Base.logger = Logger.new(File::NULL)
Minitest.after_run do
  ActiveRecord::Base.connection_pool.disconnect!
  File.delete(DATABASE) if File.exist?(DATABASE)
end

class NevaehBacklogPersistenceTest < Minitest::Test
  def setup
    Rails.env = "test"
    ENV["NEVAEH_BACKLOG_ENABLED"] = "1"
    ENV.delete("NEVAEH_BACKLOG_ACTOR_ID")
    [Marlon::TicketEvent, Marlon::Ticket, NevaehCapability, DymondKb::Article, DymondDispatch::WorkItem, GatekeeperOperation, StudioScene, Production, StudioProject, User].each(&:delete_all)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  def ticket(**attrs)
    Marlon::Ticket.create!({number: "CONTROL-#{SecureRandom.uuid}", title: "Controlled backlog case", category: "technical", status: "open",
      priority: "medium", urgency: 5, extra_fields: {}}.merge(attrs))
  end

  def backlog(ticket) = ticket.reload.extra_fields.fetch("nevaeh_backlog")

  def test_intake_enqueues_after_commit_and_sweep_discovers_historical_records
    old = ticket
    done = ticket(status: "resolved")
    queued = ActiveJob::Base.queue_adapter.enqueued_jobs
    assert_equal old.id, queued.first.fetch(:args).first.fetch("ticket_id")
    queued.clear
    assert_equal 1, NevaehIntelligences::ProcessBacklogJob.perform_now
    assert_equal [old.id], queued.map { |job| job[:args].first["ticket_id"] }
    refute_includes queued.map { |job| job[:args].first["ticket_id"] }, done.id
  end

  def test_unknown_ticket_is_escalated_with_actual_blocker_and_plan_never_closed
    row = ticket
    assert_equal "escalated", NevaehIntelligences::TicketBacklog.process!(ticket: row)
    state = backlog(row)
    assert_equal "investigation", state.fetch("classification")
    assert_includes state.fetch("blockers"), "Saved work order and explicit acceptance criteria are required"
    assert_equal row.id, state.dig("engineering_plan", "ticket_id")
    assert_equal "open", row.status
    assert_nil row.resolved_at
    event_count = row.events.count
    NevaehIntelligences::TicketBacklog.process!(ticket: row)
    assert_equal event_count, row.events.count, "duplicate job must not duplicate identical analysis events"
  end

  def test_native_work_order_and_kb_match_use_persisted_records
    article = DymondKb::Article.create!(title: "Known procedure", article_id: "KNOWN-1", metadata: {capability: "mail.configure"})
    NevaehCapability.create!(name: "Mail", slug: "mail.configure", domain: "mail", intent_name: "configure",
      handler: "Mail::Configure", queue: "default", priority: 5, enabled: true)
    row = ticket(extra_fields: {"required_capability" => "mail.configure", "work_type" => "update",
      "inputs" => {"domain" => "controlled.invalid"}, "acceptance_criteria" => ["Domain matches requested configuration"]})
    assert_equal "escalated", NevaehIntelligences::TicketBacklog.process!(ticket: row)
    assert_equal [article.id], backlog(row).fetch("knowledge_article_ids")
    assert_equal "mail.configure", NevaehIntelligences::WorkOrder.read!(ticket: row).fetch("intent_key")
    assert_equal "discovered_unverified", backlog(row).dig("engineering_plan", "studio203_evidence", "discovery_status")
    assert_equal false, backlog(row).fetch("implementation_verified")
    assert_equal "open", row.status
    assert_equal 1, row.events.where(action: "nevaeh_work_order_registered").count
    NevaehIntelligences::TicketBacklog.process!(ticket: row)
    assert_equal 1, row.events.where(action: "nevaeh_work_order_registered").count
  end

  def test_dependencies_and_duplicate_reference_cannot_be_treated_as_acceptance
    dependency = ticket(status: "resolved")
    row = ticket(extra_fields: {"depends_on_ticket_ids" => [dependency.id], "duplicate_of_ticket_id" => dependency.id})
    NevaehIntelligences::TicketBacklog.process!(ticket: row)
    assert backlog(row).fetch("blockers").any? { |b| b.include?("lacks verified resolution") }
    assert backlog(row).fetch("blockers").any? { |b| b.include?("Duplicate reference") }
    assert_equal "open", row.status
  end

  def test_failure_state_survives_new_model_instances_and_explicit_resume_keeps_reservation
    row = ticket
    5.times { NevaehIntelligences::TicketBacklog.record_failure!(ticket: row, error: IOError.new("controlled outage")) }
    assert_equal "escalated", NevaehIntelligences::TicketBacklog.process!(ticket: Marlon::Ticket.find(row.id))
    assert_equal 5, backlog(row).fetch("failure_count")
    fields = row.extra_fields.merge("nevaeh" => {"reservation_id" => "original", "execution_status" => "dispatch_uncertain"})
    row.update!(extra_fields: fields)
    NevaehIntelligences::TicketBacklog.resume!(ticket: row)
    assert_equal 0, backlog(row).fetch("failure_count")
    assert_equal "original", row.extra_fields.dig("nevaeh", "reservation_id")
    assert_equal "dispatch_uncertain", row.extra_fields.dig("nevaeh", "execution_status")
  end

  def test_production_analysis_preserves_execution_policy_block
    Rails.env = "production"
    row = ticket
    NevaehIntelligences::TicketBacklog.process!(ticket: row)
    assert_includes backlog(row).fetch("blockers"), "Existing Gatekeeper ticket policy disables production execution"
    assert_equal false, backlog(row).dig("engineering_plan", "execution_enabled")
  end

  def test_generic_lesson_writer_does_not_invent_a_controller_failure
    article = Gatekeeper::LessonService.record!(key: "controlled-lesson", title: "Verified mail lesson",
      capability: "mail.configure", symptom: "Domain unavailable", cause: "Missing record",
      remediation: "Create verified record", verification: "DNS lookup passed", metadata: {source_ticket_id: 123})
    refute_includes article.body, "account_plan"
    refute_includes article.body, "controller contract"
    refute article.metadata.key?("failure_signature")
    assert_equal "mail.configure", article.metadata.fetch("gatekeeper_capability")
    assert_equal 123, article.metadata.fetch("source_ticket_id")
  end
  def test_sweep_pages_with_a_fixed_ceiling_and_does_not_requeue_the_first_page
    103.times { ticket }
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    assert_equal 100, NevaehIntelligences::ProcessBacklogJob.perform_now
    jobs = ActiveJob::Base.queue_adapter.enqueued_jobs
    continuation = jobs.last.fetch(:args).first
    first_ids = jobs[0...-1].map { |j| j[:args].first.fetch("ticket_id") }
    assert_equal 100, first_ids.uniq.size
    ceiling = continuation.fetch("ceiling_id")
    newer = ticket
    jobs.clear
    assert_equal 3, NevaehIntelligences::ProcessBacklogJob.perform_now(after_id: continuation.fetch("after_id"), ceiling_id: ceiling)
    second_ids = jobs.map { |j| j[:args].first.fetch("ticket_id") }
    assert_empty first_ids & second_ids
    refute_includes second_ids, newer.id
  end

  def test_missing_kb_table_is_retried_then_escalated_without_closure
    row = ticket
    DymondKb::Article.connection.rename_table(:dymond_kb_articles, :unavailable_articles)
    DymondKb::Article.reset_column_information
    4.times do
      assert_raises(RuntimeError) { NevaehIntelligences::ProcessBacklogJob.new.perform(ticket_id: row.id) }
    end
    assert_equal "escalated", NevaehIntelligences::ProcessBacklogJob.new.perform(ticket_id: row.id)
    assert_equal "escalated", NevaehIntelligences::ProcessBacklogJob.new.perform(ticket_id: row.id)
    assert_equal 5, backlog(row).fetch("failure_count")
    assert_equal "open", row.status
    assert_nil row.resolved_at
  ensure
    DymondKb::Article.connection.rename_table(:unavailable_articles, :dymond_kb_articles)
    DymondKb::Article.reset_column_information
  end

  def test_disabled_automation_does_not_enqueue_or_mutate
    ENV["NEVAEH_BACKLOG_ENABLED"] = "0"
    row = ticket
    assert_empty ActiveJob::Base.queue_adapter.enqueued_jobs
    assert_equal "disabled", NevaehIntelligences::ProcessBacklogJob.perform_now(ticket_id: row.id)
    assert_equal({}, row.reload.extra_fields)
  end

  def test_invalid_work_order_is_preserved_for_review
    row = ticket(extra_fields: {"nevaeh_work_order" => {"version" => 999}})
    assert_equal "escalated", NevaehIntelligences::TicketBacklog.process!(ticket: row)
    assert_equal({"version" => 999}, row.reload.extra_fields.fetch("nevaeh_work_order"))
    assert backlog(row).fetch("blockers").any? { |b| b.include?("Unsupported work-order version") }
    assert_equal "open", row.status
  end

  def test_studio_verifier_cannot_claim_unrelated_acceptance_criteria
    assert NevaehIntelligences::TicketExecution.backlog_acceptance_supported?(
      {"acceptance_criteria" => ["Project and production persisted"]})
    refute NevaehIntelligences::TicketExecution.backlog_acceptance_supported?(
      {"acceptance_criteria" => ["Deploy to production with billing enabled"]})
    refute NevaehIntelligences::TicketExecution.backlog_acceptance_supported?({"acceptance_criteria" => []})
  end

  def test_resume_cannot_reopen_resolved_ticket
    row = ticket(status: "resolved")
    assert_raises(NevaehIntelligences::WorkOrder::Invalid) { NevaehIntelligences::TicketBacklog.resume!(ticket: row) }
    assert_equal "resolved", row.reload.status
    assert_empty ActiveJob::Base.queue_adapter.enqueued_jobs
  end

  def completed_work(criteria: ["Project and production persisted"])
    row = ticket
    order = NevaehIntelligences::WorkOrder.template.merge("objective" => "Controlled project creation",
      "inputs" => {"name" => "Controlled project"}, "acceptance_criteria" => criteria,
      "execution_policy" => {"environment" => "test", "approval" => "gatekeeper"})
    NevaehIntelligences::WorkOrder.attach!(ticket: row, attributes: order)
    project = StudioProject.create!(name: "Controlled project")
    production = Production.create!(studio_project_id: project.id)
    scene = StudioScene.create!(studio_project_id: project.id, production_id: production.id)
    item = DymondDispatch::WorkItem.create!(kind: "studio.project.create", status: "done", subject_type: "Marlon::Ticket",
      subject_id: row.id, correlation_id: SecureRandom.uuid, result: {"mutation" => "created", "project_id" => project.id,
        "production_id" => production.id, "default_scene_id" => scene.id,
        "project_persisted" => true, "production_persisted" => true, "scene_persisted" => true})
    fields = row.extra_fields.merge("nevaeh_backlog" => {"status" => "executing"}, "nevaeh" => {
      "work_item_id" => item.id, "correlation_id" => item.correlation_id, "expected_project_name" => project.name,
      "execution_status" => "dispatched", "work_order_sha256" => NevaehIntelligences::TicketApproval.fingerprint(order),
      "inputs_sha256" => NevaehIntelligences::TicketApproval.fingerprint(order.fetch("inputs"))})
    row.update!(status: "in_progress", extra_fields: fields)
    [row, item]
  end

  def test_reconciliation_records_kb_before_resolving_and_is_idempotent
    row, item = completed_work
    assert_equal "resolved", NevaehIntelligences::TicketExecution.reconcile!(ticket: row)
    assert_equal "resolved", row.reload.status
    assert_equal 1, DymondKb::Article.count
    article = DymondKb::Article.first
    assert_equal row.id, article.metadata.fetch("source_ticket_id")
    assert_equal item.id, JSON.parse(article.body.split("## Verification").last.strip).fetch("work_item_id")
    assert_equal article.id, row.extra_fields.dig("nevaeh", "knowledge_article_id")
    assert_equal "resolved", NevaehIntelligences::TicketExecution.reconcile!(ticket: Marlon::Ticket.find(row.id))
    assert_equal 1, DymondKb::Article.count
    assert_equal 1, row.events.where(action: "nevaeh_verified_and_resolved").count
  end

  def test_kb_write_failure_rolls_back_closure_and_resume_does_not_repeat_creation
    row, = completed_work
    DymondKb::Article.connection.rename_table(:dymond_kb_articles, :unavailable_articles)
    DymondKb::Article.reset_column_information
    assert_raises(Gatekeeper::LessonService::KnowledgeBaseUnavailable) do
      NevaehIntelligences::TicketExecution.reconcile!(ticket: row)
    end
    assert_equal "in_progress", row.reload.status
    assert_nil row.resolved_at
    assert_equal "dispatched", row.extra_fields.dig("nevaeh", "execution_status")
    DymondKb::Article.connection.rename_table(:unavailable_articles, :dymond_kb_articles)
    DymondKb::Article.reset_column_information
    assert_equal "resolved", NevaehIntelligences::TicketExecution.reconcile!(ticket: row)
    assert_equal 1, StudioProject.count
  ensure
    if ActiveRecord::Base.connection.table_exists?(:unavailable_articles)
      DymondKb::Article.connection.rename_table(:unavailable_articles, :dymond_kb_articles)
      DymondKb::Article.reset_column_information
    end
  end

  def test_done_work_with_unsupported_acceptance_remains_unresolved
    row, = completed_work(criteria: ["An actual release is deployed and billing works"])
    assert_equal "verification_failed", NevaehIntelligences::TicketExecution.reconcile!(ticket: row)
    assert_equal "in_progress", row.reload.status
    assert_nil row.resolved_at
    assert_equal 0, DymondKb::Article.count
  end

  def test_foreign_work_item_cannot_resolve_backlog_ticket
    row, item = completed_work
    item.update!(subject_id: row.id + 100)
    assert_equal "verification_failed", NevaehIntelligences::TicketExecution.reconcile!(ticket: row)
    assert_equal "in_progress", row.reload.status
    assert_equal 0, DymondKb::Article.count
  end

  def test_native_gatekeeper_metadata_matches_real_registry_alias_and_links_related_operations
    capability = NevaehCapability.create!(name: "Deploy", slug: "gatekeeper.deploy", domain: "infrastructure",
      intent_name: "deploy", handler: "Gatekeeper::Capabilities::DeployProject", queue: "default", priority: 5,
      enabled: true, gatekeeper_capability: "deploy_project")
    article = DymondKb::Article.create!(title: "Deploy procedure", metadata: {capability: "deploy_project"})
    source = {"capability" => "deploy_project", "operation_id" => 14, "node_id" => "2", "project_id" => "1",
      "error_class" => "RuntimeError", "error_message" => "Controlled deployment failure"}
    related = ticket(extra_fields: {"gatekeeper" => source.merge("operation_id" => 20)})
    row = ticket(extra_fields: {"source" => "gatekeeper", "gatekeeper" => source})
    assert_equal "escalated", NevaehIntelligences::TicketBacklog.process!(ticket: row)
    state = backlog(row)
    assert_equal "gatekeeper.deploy", state.fetch("required_capability")
    assert_equal "operational_execution", state.fetch("classification")
    assert_equal [related.id], state.fetch("related_ticket_ids")
    assert_equal [article.id], state.fetch("knowledge_article_ids")
    assert_equal 14, state.dig("engineering_plan", "source_evidence", "operation_id")
    assert_equal "open", related.reload.status, "related operations are not automatically duplicates"
    assert_equal "open", row.status
  end

  def test_real_incident_reference_builds_native_recovery_order_without_dispatch
    item = DymondDispatch::WorkItem.create!(kind: "job", handler: "DymondCompute::TrimHandler", status: "failed", error: "IOError: closed stream")
    row = ticket(title: "WorkItem failed — job (##{item.id})", description: "Original trim failed with a closed stream")
    assert_equal "escalated", NevaehIntelligences::TicketBacklog.process!(ticket: row)
    order = NevaehIntelligences::WorkOrder.read!(ticket: row)
    assert_equal "fix", order.fetch("work_type")
    assert_equal item.id, order.dig("inputs", "original_work_item_id")
    assert_equal "DymondCompute::TrimHandler", order.dig("inputs", "handler")
    assert order.fetch("acceptance_criteria").any? { |criterion| criterion.include?("trim artifact") }
    assert_equal false, order.dig("execution_policy", "execution_enabled")
    assert_equal "failed", item.reload.status
    assert_equal "open", row.status
    NevaehIntelligences::TicketBacklog.process!(ticket: row)
    assert_equal 1, row.events.where(action: "nevaeh_work_order_registered").count
  end

  def test_repeated_analysis_preserves_native_diagnostics_without_duplicating_events
    row = ticket
    NevaehIntelligences::TicketBacklog.process!(ticket: row)
    fields = row.reload.extra_fields
    fields.fetch("nevaeh_backlog")["source_diagnostics"] = {"operation_id" => 14, "evidence" => "retained"}
    row.update!(extra_fields: fields)
    before = row.events.count
    NevaehIntelligences::TicketBacklog.process!(ticket: row)
    assert_equal "retained", backlog(row).dig("source_diagnostics", "evidence")
    assert_equal before, row.events.count
  end

  def existing_deployment_case
    operator = User.create!(role: "super_admin")
    operation = GatekeeperOperation.create!(capability: "deploy_project", status: "failed", result: {"github_run_id" => "controlled-run"})
    row = ticket(description: "Historical application boot failure", extra_fields: {"gatekeeper" => {
      "operation_id" => operation.id, "capability" => "deploy_project", "node_id" => 1, "project_id" => 1}})
    NevaehIntelligences::TicketBacklog.process!(ticket: row)
    proof = {"eager_load_passed" => true, "https_health_status" => 200, "sidekiq_service_active" => true,
      "installed_revision" => "a" * 40, "component_verified" => true, "original_github_run_id" => "controlled-run"}
    [row, operator, operation, proof]
  end

  def test_existing_implementation_acceptance_closes_once_and_preserves_original_failure
    row, operator, operation, proof = existing_deployment_case
    2.times do
      assert_equal "resolved", NevaehIntelligences::TicketExecution.resolve_existing_deployment!(
        ticket: row, actor: operator, operation: operation, verification: proof,
        cause: "Previously invalid class declaration", remediation: "Use the qualified class declaration")
    end
    assert_equal "resolved", row.reload.status
    assert_equal "verified_resolved", backlog(row).fetch("status")
    assert_equal "existing_deployed_implementation", row.extra_fields.dig("nevaeh", "verification_mode")
    assert_equal "failed", operation.reload.status
    assert_equal 1, DymondKb::Article.count
    assert_equal 1, row.events.where(action: "nevaeh_existing_implementation_verified").count
  end

  def test_existing_implementation_refuses_missing_health_and_wrong_run_evidence
    row, operator, operation, proof = existing_deployment_case
    [proof.merge("https_health_status" => 503), proof.merge("original_github_run_id" => "wrong-run")].each do |bad|
      assert_raises(NevaehIntelligences::TicketExecution::InvalidTicket) do
        NevaehIntelligences::TicketExecution.resolve_existing_deployment!(ticket: row, actor: operator,
          operation: operation, verification: bad, cause: "Existing fix", remediation: "Verified source")
      end
    end
    assert_equal "open", row.reload.status
    assert_nil row.resolved_at
    assert_equal 0, DymondKb::Article.count
  end

  def test_existing_implementation_requires_authorized_operator
    row, operator, operation, proof = existing_deployment_case
    operator.update!(role: "client")
    assert_raises(NevaehIntelligences::TicketExecution::InvalidTicket) do
      NevaehIntelligences::TicketExecution.resolve_existing_deployment!(ticket: row, actor: operator,
        operation: operation, verification: proof, cause: "Existing fix", remediation: "Verified source")
    end
    assert_equal "open", row.reload.status
    assert_equal 0, DymondKb::Article.count
  end

  def test_completed_job_receipt_survives_serialization_and_suppresses_redelivery
    row = ticket
    job = NevaehIntelligences::ProcessBacklogJob.new(ticket_id: row.id)
    serialized = job.serialize
    assert_equal "escalated", job.perform_now
    receipt = backlog(row).fetch("job_receipts").fetch(job.job_id)
    assert_equal "completed", receipt.fetch("state")
    assert_equal "escalated", receipt.fetch("outcome")
    events = row.events.count
    replay = NevaehIntelligences::ProcessBacklogJob.deserialize(serialized)
    assert_equal "escalated", replay.perform_now
    assert_equal events, row.events.count
    assert_equal 1, row.events.where(action: "nevaeh_backlog_job_completed").count
  end

end
