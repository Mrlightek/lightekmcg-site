# frozen_string_literal: true
# Extends the existing SQLite persistence harness. Host-engine boundaries in that
# harness are controlled adapters; these checks do not claim production acceptance.
require_relative "nevaeh_backlog_test"
require "active_support/concern"
require "minitest/mock"

# SQLite test translation only; the actual migration and model callbacks run intact.
ActiveRecord::ConnectionAdapters::TableDefinition.class_eval do
  def jsonb(*names, **options) = json(*names, **options)
end
require File.join(ROOT, "db/migrate/20261108010000_create_nevaeh_control_center")
CreateNevaehControlCenter.new.migrate(:up)
require File.join(ROOT, "db/migrate/20261108140000_create_nevaeh_digital_factory")
CreateNevaehDigitalFactory.new.migrate(:up)
require File.join(ROOT, "app/models/concerns/nevaeh_neural_language")
require File.join(ROOT, "app/models/nevaeh_language_model")
%w[services/nevaeh_intelligences/canonical_json services/nevaeh_intelligences/editorial_direction services/nevaeh_intelligences/writing_engine models/concerns/nevaeh_inference
   models/nevaeh_inference_model models/nevaeh_writing_profile
   services/nevaeh_intelligences/workspace_navigation models/nevaeh_workspace_preference
   models/nevaeh_workflow models/nevaeh_workflow_run
   services/nevaeh_intelligences/workflow_runner jobs/nevaeh_intelligences/workflow_run_job
   jobs/nevaeh_intelligences/workflow_sweep_job services/nevaeh_intelligences/dialogue_sequence
   services/script_builder/dialogue_generator].each { |file| require File.join(ROOT, "app", "#{file}.rb") }

class NevaehControlCenterTest < Minitest::Test
  def setup
    Rails.env = "test"
    ENV["NEVAEH_BACKLOG_ENABLED"] = "1"
    @admin = User.create!(role: "super_admin")
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end
  def teardown
    [NevaehWorkflowRun, NevaehWorkflow, NevaehWritingProfile, NevaehInferenceModel, NevaehWorkspacePreference].each(&:delete_all)
  end
  def sections
    [{"id" => "draft", "action" => "content.generate", "inputs" => {"format" => "caption", "context" => {"topic" => "Opening night"}}, "depends_on" => []}]
  end
  def workflow(**attributes)
    NevaehWorkflow.create!({creator: @admin, name: "Opening night captions", sections: sections, status: "active"}.merge(attributes))
  end
  def rule(**attributes)
    {"id" => "premiere", "format" => "caption", "keywords" => ["film"], "templates" => ["{topic}: {goal}.", "{facts}"], "weight" => 1}.merge(attributes.transform_keys(&:to_s))
  end
  def test_worker_run_is_idempotent_and_freezes_inputs
    worker = workflow
    run = NevaehIntelligences::WorkflowRunner.request!(workflow: worker, actor: @admin, request_key: "manual-request-1")
    worker.update!(name: "Renamed", sections: sections.map { |step| step.merge("id" => "changed") })
    same = NevaehIntelligences::WorkflowRunner.request!(workflow: worker, actor: @admin, request_key: "manual-request-1")
    assert_equal run.id, same.id
    assert_equal "Opening night captions", same.snapshot["name"]
    assert_equal "draft", same.snapshot["sections"].first["id"]
    NevaehIntelligences::WorkflowRunJob.perform_now(run.id)
    ticket_id = run.reload.ticket_id
    assert ticket_id
    assert_equal "dispatched", run.status
    ticket = run.ticket
    assert_equal "Opening night captions", ticket.title
    assert ticket.extra_fields.dig("nevaeh_structured", "automatic")
    assert_equal @admin.id, ticket.extra_fields.dig("nevaeh_structured", "authorized_actor_id")
    assert_equal run.snapshot["sections"], ticket.extra_fields.dig("nevaeh_work_order", "inputs", "sections")
    NevaehIntelligences::WorkflowRunJob.perform_now(run.id)
    assert_equal ticket_id, run.reload.ticket_id
  end
  def test_scheduler_claims_one_slot_and_pause_clears_next_run
    worker = workflow(interval_minutes: 5)
    assert worker.next_run_at > Time.current
    worker.update_columns(next_run_at: 1.minute.ago)
    2.times { NevaehIntelligences::WorkflowRunner.tick! }
    assert_equal 1, worker.runs.count
    assert worker.reload.next_run_at > Time.current
    worker.update!(status: "paused")
    assert_nil worker.next_run_at
    assert_raises(NevaehIntelligences::WorkOrder::Invalid) { NevaehIntelligences::WorkflowRunner.request!(workflow: worker, actor: @admin, request_key: "manual-request-2") }
  end
  def test_revocation_blocks_saved_runs_and_pauses_future_schedules
    worker = workflow(interval_minutes: 5)
    run = NevaehIntelligences::WorkflowRunner.request!(workflow: worker, actor: @admin, request_key: "manual-request-3")
    @admin.update!(role: "employee")
    NevaehIntelligences::WorkflowRunJob.perform_now(run.id)
    assert_equal "blocked", run.reload.status
    assert_nil run.ticket_id
    worker.update_columns(next_run_at: 1.minute.ago)
    NevaehIntelligences::WorkflowRunner.tick!
    assert_equal "paused", worker.reload.status
  end
  def test_backlog_disable_does_not_silently_submit_work
    run = NevaehIntelligences::WorkflowRunner.request!(workflow: workflow, actor: @admin, request_key: "manual-disabled-1")
    ENV["NEVAEH_BACKLOG_ENABLED"] = "0"
    NevaehIntelligences::WorkflowRunJob.perform_now(run.id)
    assert_equal "blocked", run.reload.status
    assert_nil run.ticket_id
  ensure
    ENV["NEVAEH_BACKLOG_ENABLED"] = "1"
  end
  def test_dependency_cycles_invalid_intervals_and_stale_edits_are_rejected
    worker = workflow
    copy = NevaehWorkflow.find(worker.id)
    worker.update!(name: "Current")
    assert_raises(ActiveRecord::StaleObjectError) { copy.update!(name: "Stale") }
    refute NevaehWorkflow.new(creator: @admin, name: "Too frequent", sections: sections, interval_minutes: 1).valid?
    invalid = sections.map { |s| s.merge("depends_on" => ["future"]) }
    refute NevaehWorkflow.new(creator: @admin, name: "Invalid graph", sections: invalid).valid?
  end
  def test_employee_cannot_request_a_worker
    employee = User.create!(role: "employee")
    assert_raises(NevaehIntelligences::WorkOrder::Invalid) { NevaehIntelligences::WorkflowRunner.request!(workflow: workflow, actor: employee, request_key: "manual-request-4") }
  end
  def test_writing_action_produces_a_verified_draft_receipt
    inputs = sections.first["inputs"]
    output = NevaehIntelligences::StructuredActions.perform("content.generate", inputs, actor: @admin, ticket: nil)
    assert_includes output["text"], "Opening night"
    assert output["draft"]
    assert NevaehIntelligences::StructuredActions.verify!("content.generate", inputs, output, actor: @admin)
    output["text"] = "tampered"
    assert_raises(NevaehIntelligences::StructuredTicket::Invalid) { NevaehIntelligences::StructuredActions.verify!("content.generate", inputs, output, actor: @admin) }
  end
  def test_rule_engine_preserves_names_facts_and_literal_values
    context = {"topic" => "Premiere", "protagonist" => "Kess", "companion" => "Ren", "goal" => "finish the show", "facts" => "The curtain rises at eight. {literal}"}
    result = NevaehIntelligences::WritingEngine.generate(format: "script", context: context)
    assert_includes result["text"], "Kess: We need to finish the show"
    assert_includes result["text"], "Ren: The curtain rises at eight. {literal}"
    assert_equal "rules", result["provider"]
    assert_raises(ArgumentError) { NevaehIntelligences::WritingEngine.generate(format: "script", context: {"topic" => ""}) }
    assert_raises(ArgumentError) { NevaehIntelligences::WritingEngine.generate(format: "script", context: {"topic" => "A", "handler" => "Kernel.system"}) }
  end
  def test_inference_model_uses_synonyms_and_exposes_match_evidence
    model = NevaehInferenceModel.create!(name: "Studio", rules: [rule], lexicon: {"film" => ["movie", "cinema"]})
    result = model.infer(format: "caption", context: {"topic" => "movie premiere", "goal" => "open tonight", "facts" => "One show."})
    assert_equal "premiere", result["matched_rule"]
    assert_equal ["film"], result["matches"].first["matched_terms"]
    assert_equal "movie premiere: open tonight. One show.", result["text"]
    refute result["fallback"]
    assert_equal 1.0, result["match_score"]
  end
  def test_inference_examples_extend_selection_and_unknown_topics_fall_back
    model = NevaehInferenceModel.create!(name: "Voice", examples: [{"format" => "post", "topic" => "music release", "templates" => ["New: {topic}.", "{facts}"]}])
    result = model.infer(format: "post", context: {"topic" => "music launch", "facts" => "Friday at noon."})
    assert_equal "example_1", result["matched_rule"]
    assert_includes result["text"], "Friday at noon."
    assert model.infer(format: "caption", context: {"topic" => "gardening"})["fallback"]
  end
  def test_required_context_and_weight_control_plan_selection
    model = NevaehInferenceModel.create!(name: "Voice", rules: [rule(id: "facts_required", requires: ["facts"], weight: 5), rule(id: "general", weight: 1)])
    assert_equal "general", model.infer(format: "caption", context: {"topic" => "film"})["matched_rule"]
    assert_equal "facts_required", model.infer(format: "caption", context: {"topic" => "film", "facts" => "Verified."})["matched_rule"]
  end
  def test_saved_writing_service_calls_native_inference_and_tracks_revision
    model = NevaehInferenceModel.create!(name: "Studio", rules: [rule])
    profile = NevaehWritingProfile.create!(name: "Caption writer", format: "caption", provider: "inference", inference_model: model)
    result = NevaehIntelligences::WritingEngine.generate(format: "caption", context: {"topic" => "film"}, profile: profile.contract)
    assert_equal model.id, result.dig("inference", "model_id")
    fingerprint = result.dig("inference", "model_sha256")
    model.update!(rules: [rule(weight: 2)])
    refute_equal fingerprint, model.infer(format: "caption", context: {"topic" => "film"})["model_sha256"]
    model.update!(enabled: false)
    assert_raises(ArgumentError) { NevaehIntelligences::WritingEngine.generate(format: "caption", context: {"topic" => "film"}, profile: profile.contract) }
  end
  def test_invalid_inference_rules_and_template_tokens_are_rejected
    refute NevaehInferenceModel.new(name: "Bad", rules: [rule(templates: ["{unknown}"])]).valid?
    refute NevaehInferenceModel.new(name: "Bad", rules: [rule, rule]).valid?
    refute NevaehInferenceModel.new(name: "Bad", rules: [rule(weight: 11)]).valid?
    refute NevaehWritingProfile.new(name: "Bad", format: "caption", provider: "inference").valid?
  end
  def test_sidebar_reordering_preserves_system_permission_filters
    defaults = [{"id" => "nevaeh", "path" => "/employee/nevaeh/control-center", "label" => "Nevaeh", "group" => "System", "icon" => "ti-brain"}]
    saved = [{"id" => "nevaeh", "path" => "/evil", "label" => "Brain", "group" => "Home", "hidden" => false}, {"id" => "vault", "path" => "/dashboard/vault", "label" => "Vault", "group" => "Home"}, {"id" => "custom-live", "path" => "/dashboard/live", "label" => "Live", "group" => "Studio", "hidden" => true}]
    preference = NevaehWorkspacePreference.create!(user: @admin, navigation: saved)
    result = NevaehIntelligences::WorkspaceNavigation.entries(user: @admin, defaults: defaults)
    assert_equal %w[nevaeh custom-live], result.map { |r| r["id"] }
    assert_equal "/employee/nevaeh/control-center", result.first["path"]
    assert_equal "Brain", result.first["label"]
    assert result.last["hidden"]
    assert_equal saved.length, preference.navigation.length
  end
  def test_sidebar_rejects_remote_script_and_traversal_paths
    ["//evil.test", "javascript:alert(1)", "/foo/../bar", "/foo\\bar", "/foo?next=https://evil.test"].each do |path|
      assert_raises(ArgumentError) { NevaehIntelligences::WorkspaceNavigation.normalize([{"id" => "custom-app", "label" => "App", "group" => "Apps", "path" => path}]) }
    end
    result = NevaehIntelligences::WorkspaceNavigation.normalize([{"id" => "custom-studio", "label" => "Studio", "group" => "Create", "path" => "/lightek/index.html#/studio"}])
    assert_equal "/lightek/index.html#/studio", result.first["path"]
  end
  def test_legacy_script_generator_uses_connected_beats_and_stable_cast
    script = ScriptBuilder::DialogueGenerator.new(protagonist: {name: "Kess"}, companion: {name: "Ren"}).generate_scene(topic: "opening night", line_count: 6)
    assert_equal 3, script.lines.count { |line| line.start_with?("KESS:") }
    assert_equal 3, script.lines.count { |line| line.start_with?("REN:") }
    assert_includes script, "opening night"
    assert_includes script, "test the uncertain part first"
  end
end
