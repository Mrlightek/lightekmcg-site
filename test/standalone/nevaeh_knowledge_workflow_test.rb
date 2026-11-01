# frozen_string_literal: true
# Real persisted ticket/KB contracts without the private Rails engines. External
# mail submission is a test boundary; these are not production delivery proofs.
require "minitest/autorun"
require "minitest/mock"
require "active_record"
require "active_job"
require "active_support/all"
require "logger"
require "pathname"

module Rails
  def self.env = ActiveSupport::StringInquirer.new("test")
  def self.root = Pathname.new(File.expand_path("../..", __dir__))
  def self.logger = Logger.new(File::NULL)
end
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table(:request_sites) { |t| t.integer :user_id; t.string :name }
  create_table(:request_pages) { |t| t.integer :request_site_id; t.string :title; t.string :slug; t.boolean :published; t.integer :position }
  create_table(:request_sections) { |t| t.integer :request_page_id; t.string :kind; t.json :data; t.integer :position }
  create_table(:nevaeh_ticket_templates) { |t| t.integer :user_id; t.string :name; t.json :sections, default: []; t.timestamps }
  create_table(:gatekeeper_installations) { |t| t.integer :account_id; t.string :domain; t.boolean :enabled, default: true; t.string :nevaeh_reporting_secret_slug }
  create_table(:users) { |t| t.string :role; t.string :email_address }
  create_table(:nevaeh_capabilities) { |t| t.string :slug; t.boolean :enabled; t.string :handler; t.string :gatekeeper_capability; t.json :metadata; t.timestamps }
  create_table(:dymond_kb_articles) { |t| t.string :article_id; t.string :slug; t.string :title; t.string :article_type; t.text :body; t.json :metadata; t.timestamps }
  create_table(:marlon_tickets) do |t|
    %i[number category title description priority status organization_name reseller_id assigned_team assigned_rep related_type].each { |name| t.string name }
    t.integer :urgency; t.integer :submitted_by_id; t.integer :related_id; t.json :extra_fields; t.datetime :resolved_at; t.timestamps
  end
  create_table(:marlon_ticket_events) { |t| t.integer :ticket_id; t.integer :actor_id; t.string :action; t.text :detail; t.timestamps }
  create_table(:lightek_mail_accounts) { |t| t.integer :user_id; t.boolean :ready }
end
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
class ApplicationJob < ActiveJob::Base; end
ActiveJob::Base.queue_adapter = :test
ActiveJob::Base.logger = Logger.new(File::NULL)
class User < ApplicationRecord; end
class GatekeeperInstallation < ApplicationRecord
  belongs_to :account, class_name: "User", optional: true
  def eligible? = enabled?
end
module LightekVault
  class Service
    class AccessDenied < StandardError; end
  end
end
# Permission fixture: production CanCan rules are exercised by native checks.
class Ability
  def initialize(actor) = @actor = actor
  def can?(action, _subject) = action == :create || %w[admin super_admin].include?(@actor.role)
end
class NevaehCapability < ApplicationRecord; end
module DymondKb
  class Article < ApplicationRecord
    self.table_name = "dymond_kb_articles"
  end
end
class RequestSite < ApplicationRecord
  has_many :pages, class_name: "RequestPage"
end
class RequestPage < ApplicationRecord
  belongs_to :request_site
  has_many :sections, class_name: "RequestSection"
end
class RequestSection < ApplicationRecord
  belongs_to :request_page
end
module LightekSettings
  module WebsiteIdentity
    def self.sites_for(actor) = RequestSite.where(user_id: actor.id)
  end
end
module LightekDesign
  module Catalog
    def self.section_definition(kind) = kind == "hero" ? {"fields" => [{"name" => "title"}]} : nil
  end
end
module Gatekeeper
  def self.authorize_capability!(**) = raise("Gatekeeper must be supplied by the installed runtime")
end
module LightekMail
  class Account < ApplicationRecord
    self.table_name = "lightek_mail_accounts"
    def sending_ready? = ready?
  end
  class Submission
    def self.create!(**) = raise("Unstubbed mail transport")
  end
end
module NevaehIntelligences
  class TicketBacklog
    def self.enabled? = false
  end
end
require_relative "../../app/models/marlon/ticket_categories"
require_relative "../../app/models/marlon/ticket"
require_relative "../../app/models/marlon/ticket_event"
require_relative "../../app/services/nevaeh_intelligences/work_order"
require_relative "../../app/services/nevaeh_intelligences/ticket_approval"
require_relative "../../app/services/nevaeh_intelligences/structured_ticket"
require_relative "../../app/services/nevaeh_intelligences/structured_execution"
require_relative "../../app/services/nevaeh_intelligences/structured_actions"
Dir[File.expand_path("../../app/services/nevaeh_intelligences/structured_workers/*.rb", __dir__)].sort.each { |path| require path }
require_relative "../../app/services/nevaeh_intelligences/knowledge_procedures"
require_relative "../../app/services/nevaeh_intelligences/teach_core_procedures"
require_relative "../../app/services/nevaeh_orchestration/escalation"
require_relative "../../app/models/nevaeh_ticket_template"
require_relative "../../app/services/gatekeeper/fleet/rollouts"
require_relative "../../app/services/nevaeh_intelligences/lesson_distribution"
require_relative "../../app/services/studio/native_blender/media_presets"
require_relative "../../app/services/nevaeh_intelligences/central_reporting"
require_relative "../../app/jobs/nevaeh_intelligences/knowledge_gap_notification_job"
require_relative "../../app/services/gatekeeper/lesson_service"

class NevaehKnowledgeWorkflowTest < Minitest::Test
  Procedures = NevaehIntelligences::KnowledgeProcedures
  Structured = NevaehIntelligences::StructuredTicket
  def setup
    [NevaehTicketTemplate, GatekeeperInstallation, RequestSection, RequestPage, RequestSite, Marlon::TicketEvent, Marlon::Ticket, DymondKb::Article, NevaehCapability, LightekMail::Account, User].each(&:delete_all)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    @admin = User.create!(role: "super_admin", email_address: "admin@example.com")
    @client = User.create!(role: "client", email_address: "client@example.com")
    @cap = NevaehCapability.create!(slug: Structured::CAPABILITY, handler: Structured::HANDLER, gatekeeper_capability: Structured::CAPABILITY, enabled: true)
    @rows = JSON.parse(File.read(Rails.root.join("config/nevaeh/procedures/core.json")))
    @rows.each do |row|
      DymondKb::Article.create!(article_id: row.fetch("key"), title: row.fetch("contract").fetch("label"), body: row.fetch("body"), metadata: {Procedures::KEY => row.fetch("contract")})
    end
  end
  def ticket
    Marlon::Ticket.create!(title: "Controlled request", category: "technical", priority: "medium", urgency: 5, status: "open", extra_fields: {})
  end
  def step
    {"id" => "page", "action" => "site.page.create", "inputs" => {"site_id" => "1", "title" => "About", "slug" => "about"}}
  end
  def article
    DymondKb::Article.find_by!(article_id: "nevaeh-request-create-page")
  end
  def change_contract(values)
    metadata = article.metadata.deep_dup
    metadata.fetch(Procedures::KEY).merge!(values)
    article.update!(metadata: metadata)
  end

  def test_only_available_unambiguous_executable_kb_lessons_are_offered
    assert_equal 5, Procedures.available.size
    change_contract("status" => "draft")
    refute Procedures.available.key?(step["action"])
    change_contract("status" => "available", "action" => "shell.run")
    refute Procedures.available.key?("shell.run")
  end
  def test_article_cannot_substitute_an_unregistered_backend_worker
    assert_equal "NevaehIntelligences::StructuredWorkers::CreatePage", Procedures.fetch!(step["action"]).fetch("worker")
    change_contract("worker" => "Kernel")
    assert_raises(Procedures::Invalid) { Procedures.fetch!(step["action"]) }
  end
  def test_missing_or_disabled_registration_removes_requests
    @cap.update!(enabled: false)
    assert_empty Procedures.available
    @cap.update!(enabled: true, handler: "UnregisteredHandler")
    assert_empty Procedures.available
  end
  def test_duplicate_article_owners_are_rejected
    DymondKb::Article.create!(article_id: "duplicate", metadata: article.metadata, body: article.body)
    assert_raises(Procedures::Invalid) { Procedures.fetch!(step["action"]) }
  end
  def test_invalid_schema_and_missing_acceptance_cannot_advertise_requests
    change_contract("inputs" => {"command" => {"type" => "text", "required" => true, "label" => "Command"}})
    assert_raises(Procedures::Invalid) { Procedures.fetch!(step["action"]) }
    change_contract("inputs" => @rows.first.fetch("contract").fetch("inputs"), "acceptance_criteria" => [])
    assert_raises(Procedures::Invalid) { Procedures.fetch!(step["action"]) }
  end
  def test_saved_work_contains_the_actual_kb_revision_and_acceptance
    record = ticket
    order = Structured.attach!(ticket: record, actor: @client, sections: [step])
    saved = order.dig("inputs", "sections").first
    assert_equal article.id, saved.dig("procedure", "article_id")
    assert_equal 64, saved.dig("procedure", "sha256").length
    assert Procedures.validate_steps!([saved])
    assert_equal @rows.first.fetch("contract").fetch("acceptance_criteria").map { |text| "page: #{text}" }, order["acceptance_criteria"]
    assert_nil record.reload.extra_fields.dig("nevaeh_structured", "authorized_revision")
  end
  def test_customer_cannot_enable_automatic_execution
    record = ticket
    assert_raises(Structured::Invalid) { Structured.attach!(ticket: record, actor: @client, sections: [step], automatic: true) }
    assert_nil record.reload.extra_fields["nevaeh_work_order"]
  end
  def test_operator_automatic_approval_is_bound_to_saved_contract
    record = ticket
    order = Structured.attach!(ticket: record, actor: @admin, sections: [step], automatic: true)
    assert_equal NevaehIntelligences::TicketApproval.fingerprint(order), record.reload.extra_fields.dig("nevaeh_structured", "authorized_revision")
  end
  def test_changed_or_withdrawn_lesson_invalidates_authorized_work
    saved = Structured.compile([step], bind_procedures: true)
    article.update!(body: "Amended operational lesson")
    assert_raises(Procedures::Invalid) { Procedures.validate_steps!(saved) }
    change_contract("status" => "withdrawn")
    assert_raises(Procedures::Invalid) { Structured.compile([step], bind_procedures: true) }
  end
  def test_stale_form_binding_cannot_be_silently_replaced
    form = step.merge("procedure" => Procedures.bind!(step["action"]).transform_values(&:to_s))
    assert_equal article.id, Structured.compile([form], bind_procedures: true).first.dig("procedure", "article_id")
    article.update!(body: "Changed after the form was opened")
    assert_raises(Procedures::Invalid) { Structured.compile([form], bind_procedures: true) }
  end
  def test_legacy_orders_remain_readable_but_cannot_execute_without_a_lesson
    compiled = Structured.compile([step])
    assert_equal "site.page.create", compiled.first["action"]
    assert_raises(Procedures::Invalid) { Procedures.validate_steps!(compiled) }
  end
  def test_dependency_outputs_still_compile_into_the_same_work_order
    section = {"id" => "hero", "action" => "site.section.add", "inputs" => {"site_id" => 1, "page_id" => "@page.page_id", "kind" => "hero", "data" => {"title" => "Hello"}}}
    saved = Structured.compile([step, section], bind_procedures: true)
    assert_equal ["page"], saved.last["depends_on"]
    assert Procedures.validate_steps!(saved)
  end
  def test_repeat_escalation_reuses_original_ticket_and_routes_to_people
    record = ticket
    2.times { NevaehOrchestration::Escalation.knowledge_gap!(ticket: record, reason: "A lesson needs implementation") }
    assert_equal 1, Marlon::Ticket.count
    assert_equal "Technical Team", record.reload.assigned_team
    assert_equal "User:#{@admin.id}", record.assigned_rep
    assert_equal 1, record.events.where(action: "nevaeh_knowledge_gap_escalated").count
    assert_equal "pending", record.extra_fields.dig("nevaeh_knowledge_gap", "notification", "state")
  end
  def test_escalation_notification_uses_existing_mail_outbox_and_is_not_repeated
    record = ticket
    NevaehOrchestration::Escalation.knowledge_gap!(ticket: record, reason: "Teach a new capability")
    LightekMail::Account.create!(user_id: @admin.id, ready: true)
    calls = []
    submit = ->(**args) { calls << args; Struct.new(:id).new(99) }
    LightekMail::Submission.stub(:create!, submit) do
      2.times { NevaehIntelligences::KnowledgeGapNotificationJob.new.perform(record.id) }
    end
    assert_equal 1, calls.size
    assert_equal "nevaeh_gap_#{record.id}_#{@admin.id}", calls.first.fetch(:idempotency_key)
    assert_equal @admin.email_address, calls.first.dig(:attributes, :to)
    assert_equal [99], record.reload.extra_fields.dig("nevaeh_knowledge_gap", "notification", "message_ids")
  end
  def test_unconfigured_notification_keeps_real_blocker_for_recovery
    record = ticket
    NevaehOrchestration::Escalation.knowledge_gap!(ticket: record, reason: "Missing lesson")
    assert_raises(NevaehIntelligences::KnowledgeGapNotificationJob::Unavailable) { NevaehIntelligences::KnowledgeGapNotificationJob.new.perform(record.id) }
    state = record.reload.extra_fields.dig("nevaeh_knowledge_gap", "notification")
    assert_equal "pending", state["state"]
    assert_includes state["blocker"], "mailbox"
  end
  def test_escalated_ticket_cannot_be_manually_closed_as_solved
    record = ticket
    NevaehOrchestration::Escalation.knowledge_gap!(ticket: record, reason: "Missing lesson")
    refute record.update(status: "resolved")
    assert_equal "open", record.reload.status
  end
  def test_verified_evidence_enriches_knowledge_without_invalidating_other_requests
    record = ticket
    steps = Structured.compile([step], bind_procedures: true)
    completed = {"page" => {"status" => "verified", "output" => {"page_id" => 2}}}
    Procedures.record_verification!(ticket: record, steps: steps, completed: completed, solution_article: article)
    assert Procedures.validate_steps!(steps)
    assert_equal article.id, article.reload.metadata.dig("nevaeh_verified_executions", record.id.to_s, "solution_article_id")
    completed["page"]["status"] = "failed"
    assert_raises(Procedures::Invalid) { Procedures.record_verification!(ticket: record, steps: steps, completed: completed, solution_article: article) }
  end
  def execution_ticket(sections)
    record = ticket
    order = Structured.attach!(ticket: record, actor: @admin, sections: sections, automatic: true)
    fields = record.reload.extra_fields
    fields["nevaeh"] = {"actor_id" => @admin.id, "reservation_id" => "controlled-reservation", "work_order_sha256" => NevaehIntelligences::TicketApproval.fingerprint(order)}
    record.update!(extra_fields: fields)
    record
  end
  def test_actual_backend_worker_executes_verifies_teaches_and_closes
    site = RequestSite.create!(user_id: @admin.id, name: "Controlled site")
    record = execution_ticket([step.deep_merge("inputs" => {"site_id" => site.id})])
    NevaehOrchestration::Escalation.knowledge_gap!(ticket: record, reason: "Operator taught this procedure")
    Gatekeeper.stub(:authorize_capability!, @admin) do
      NevaehIntelligences::StructuredExecution.execute!(ticket: record, reservation: "controlled-reservation")
    end
    assert_equal 1, site.pages.count
    assert_equal "about", site.pages.first.slug
    refute site.pages.first.published?
    assert_equal "resolved", record.reload.status
    assert_equal "verified", record.extra_fields.dig("nevaeh", "execution_status")
    assert_equal "learned", record.extra_fields.dig("nevaeh_knowledge_gap", "state")
    assert DymondKb::Article.find_by(article_id: "nevaeh-structured-ticket-#{record.id}")
    assert article.reload.metadata.dig("nevaeh_verified_executions", record.id.to_s)
  end
  def test_failed_followup_keeps_verified_receipt_and_restart_does_not_repeat_work
    site = RequestSite.create!(user_id: @admin.id, name: "Controlled site")
    page = step.deep_merge("inputs" => {"site_id" => site.id})
    section = {"id" => "hero", "action" => "site.section.add", "inputs" => {"site_id" => site.id, "page_id" => "@page.page_id", "kind" => "hero", "data" => {"title" => "Welcome"}}}
    record = execution_ticket([page, section])
    attempts = 0
    worker = NevaehIntelligences::StructuredWorkers::AddSection
    original = worker.method(:perform)
    unstable = ->(*args, **kwargs) do
      attempts += 1
      raise Structured::Invalid, "Controlled temporary implementation failure" if attempts == 1
      original.call(*args, **kwargs)
    end
    Gatekeeper.stub(:authorize_capability!, @admin) do
      worker.stub(:perform, unstable) do
        assert_raises(Structured::Invalid) { NevaehIntelligences::StructuredExecution.execute!(ticket: record, reservation: "controlled-reservation") }
        assert_equal "verified", record.reload.extra_fields.dig("nevaeh_structured", "steps", "page", "status")
        assert_equal "open", record.status
        # New handler invocation simulates the persisted restart boundary.
        NevaehIntelligences::StructuredExecution.execute!(ticket: Marlon::Ticket.find(record.id), reservation: "controlled-reservation")
      end
    end
    assert_equal 1, site.pages.count
    assert_equal 1, site.pages.first.sections.count
    assert_equal "resolved", record.reload.status
    assert_equal 2, record.extra_fields.dig("nevaeh_structured", "steps").size
  end
  def test_github_source_cannot_bypass_gatekeeper_revision_authorization
    record = execution_ticket([step])
    fields = record.extra_fields.deep_dup
    fields["nevaeh_github"] = {"source_sha256" => "a" * 64}
    record.update!(extra_fields: fields)
    assert_raises(Structured::Invalid) { NevaehIntelligences::StructuredExecution.authorize!(ticket: record) }
    fields["nevaeh_github_authorization"] = {"source_sha256" => "a" * 64, "work_order_sha256" => fields.fetch("nevaeh").fetch("work_order_sha256")}
    record.update!(extra_fields: fields)
    assert_equal @admin.id, NevaehIntelligences::StructuredExecution.authorize!(ticket: record).id
    fields["nevaeh_github"]["source_sha256"] = "b" * 64
    record.update!(extra_fields: fields)
    assert_raises(Structured::Invalid) { NevaehIntelligences::StructuredExecution.authorize!(ticket: record) }
  end
  def test_ticket_templates_crud_preserves_user_scope_and_does_not_dispatch
    saved = NevaehTicketTemplate.create!(user: @client, name: "Reusable page", sections: [step])
    assert_equal 1, NevaehTicketTemplate.for_user(@client).count
    assert_empty NevaehTicketTemplate.for_user(@admin)
    assert_equal article.id, saved.reusable_sections!.first.dig("procedure", "article_id")
    assert_equal 0, Marlon::Ticket.count
    saved.update!(name: "Our about page")
    assert_equal "Our about page", saved.reload.name
    article.update!(body: "Changed lesson requires review")
    assert_raises(Procedures::Invalid) { saved.reusable_sections! }
    saved.destroy!
    assert_empty NevaehTicketTemplate.for_user(@client)
  end
  def test_movie_template_is_pinned_to_the_actual_original_json_preset
    worker = NevaehIntelligences::StructuredWorkers::CreateMovieProject
    definition = Procedures.fetch!(worker::ACTION)
    inputs = definition.fetch("defaults")
    assert_equal "film/proof_of_concept", worker.preset!(inputs)
    assert_equal 4096, worker.values!(inputs).fetch("resolution_x")
    assert_raises(Structured::Invalid) { worker.values!(inputs.deep_merge("data" => {"fps" => "NaN"})) }
    assert_raises(Structured::Invalid) { worker.values!(inputs.deep_merge("data" => {"command" => "anything"})) }
    assert_raises(Structured::Invalid) { worker.preset!(inputs.merge("preset_key" => "base/production_preset")) }
  end
  def test_central_reports_reuse_the_ticket_and_derive_account_from_installation
    installation = GatekeeperInstallation.create!(domain: "client.example.com", account: @client)
    source = {"version" => 1, "ticket_id" => 42, "number" => "LT-REAL", "title" => "Teach a request", "description" => "Client request details", "reason" => "Missing registered lesson", "account_id" => @admin.id}
    first = NevaehIntelligences::CentralReporting.receive!(installation: installation, payload: source)
    second = NevaehIntelligences::CentralReporting.receive!(installation: installation, payload: source)
    assert_equal first.id, second.id
    assert_equal 1, Marlon::Ticket.count
    assert_equal @client.id, first.submitted_by_id
    assert_equal @client.id, first.extra_fields.dig("nevaeh_remote", "account_id")
    refute first.extra_fields.dig("nevaeh_remote", "payload").key?("account_id")
    assert_equal "Technical Team", first.reload.assigned_team
  end
  def test_signed_installation_identity_body_and_timestamp_are_enforced
    reporting = NevaehIntelligences::CentralReporting
    installation = GatekeeperInstallation.create!(domain: "client.example.com", account: @client, nevaeh_reporting_secret_slug: "fixture-key")
    timestamp = Time.now.to_i.to_s
    body = '{"version":1}'
    signed = reporting.signature("fixture-token", timestamp, body)
    reporting.stub(:settings, {"enabled" => true}) do
      reporting.stub(:credential, "fixture-token") do
        assert_equal installation.id, reporting.authenticate!(installation_id: installation.id, timestamp: timestamp, supplied: signed, body: body).id
        assert_raises(reporting::Invalid) { reporting.authenticate!(installation_id: installation.id, timestamp: timestamp, supplied: signed, body: body + " ") }
        assert_raises(reporting::Invalid) { reporting.authenticate!(installation_id: installation.id, timestamp: (Time.now.to_i - 600).to_s, supplied: signed, body: body) }
        installation.update!(enabled: false)
        assert_raises(reporting::Invalid) { reporting.authenticate!(installation_id: installation.id, timestamp: timestamp, supplied: signed, body: body) }
      end
    end
  end
  def test_client_forwarding_persists_the_snapshot_and_does_not_repeat_completed_reports
    record = ticket
    NevaehOrchestration::Escalation.knowledge_gap!(ticket: record, reason: "Teach a new worker")
    keys = NevaehIntelligences::CentralReporting::KEYS
    previous = keys.to_h { |key| [key, ENV[key]] }
    ENV["NEVAEH_CENTRAL_URL"] = "https://main.example.com/gatekeeper/callbacks/nevaeh_escalation"
    ENV["NEVAEH_INSTALLATION_ID"] = "10"
    ENV["NEVAEH_CENTRAL_TOKEN"] = "fixture-token"
    calls = []
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.instance_variable_set(:@read, true)
    response.body = JSON.generate({"ticket_id" => 900, "ticket_number" => "LT-CENTRAL"})
    http = Object.new
    http.define_singleton_method(:request) do |request|
      calls << request
      assert_body = Marlon::Ticket.find(record.id).extra_fields.dig("nevaeh_knowledge_gap", "notification", "report_body")
      raise "Snapshot was not committed before sending" unless assert_body == request.body
      response
    end
    start = ->(*_args, **_options, &block) { block.call(http) }
    Net::HTTP.stub(:start, start) do
      2.times { NevaehIntelligences::KnowledgeGapNotificationJob.new.perform(record.id) }
    end
    assert_equal 1, calls.size
    assert_equal "10", calls.first["X-Lightek-Installation"]
    assert_equal "reported_to_central", record.reload.extra_fields.dig("nevaeh_knowledge_gap", "notification", "state")
    assert_equal 900, record.extra_fields.dig("nevaeh_knowledge_gap", "notification", "central_ticket_id")
  ensure
    previous&.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
  end
  def test_knowledge_distribution_requires_current_revision_proof_and_preserves_local_edits
    distribution = NevaehIntelligences::LessonDistribution
    assert_raises(Procedures::Invalid) { distribution.export!(ids: [article.id], actor: @admin) }
    steps = Structured.compile([step], bind_procedures: true)
    Procedures.record_verification!(ticket: ticket, steps: steps, completed: {"page" => {"status" => "verified"}}, solution_article: article)
    bundle = distribution.export!(ids: [article.id], actor: @admin)
    assert_equal 1, distribution.import!(bundle).fetch("lessons")
    article.update!(body: "Local client customization")
    assert_raises(Procedures::Invalid) { distribution.import!(bundle) }
    assert_equal "Local client customization", article.reload.body
    bundle["lessons"].first["body"] = "Tampered in transit"
    assert_raises(Procedures::Invalid) { distribution.import!(bundle) }
  end
  def test_reteaching_on_release_preserves_instance_amendments
    article.update!(body: "Instance-specific amended lesson")
    NevaehIntelligences::TeachCoreProcedures.call
    assert_equal "Instance-specific amended lesson", article.reload.body
    assert_equal 5, DymondKb::Article.count
  end
end
