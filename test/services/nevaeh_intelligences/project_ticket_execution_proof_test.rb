# frozen_string_literal: true
require "test_helper"
require "json"

# This exercises the REAL intelligence -> Nevaeh -> Gatekeeper path.
# Only the background queue boundary is driven inline for deterministic proof.
# It is NOT a claim that production queues were verified.
class NevaehProjectTicketExecutionProofTest < ActiveSupport::TestCase
  test "ticket intent dispatch creates project production scene and ticket evidence" do
    capability = NevaehCapability.find_or_initialize_by(slug: "studio.project.create")
    capability.assign_attributes(
      name: "Studio Project Create", domain: "studio", intent_name: "create_studio_project",
      handler: "Studio::Workers::ProjectCreation", queue: "default", priority: 5,
      gatekeeper_capability: "studio.project.create",
      event_types: ["studio.project.create.requested"], enabled: true
    )
    capability.save!

    intelligence = NevaehIntelligence.find_or_initialize_by(intent_key: capability.slug)
    intelligence.assign_attributes(
      name: "Create Studio project", target_model: "StudioProject",
      operation: "create", status: "published", execution_mode: "async",
      nevaeh_capability: capability,
      instructions: {"action" => "create", "event_type" => "studio.project.create.requested"}
    )
    intelligence.save!

    ticket = Marlon::Ticket.create!(
      title: "Proof: Nevaeh creates a Studio project",
      category: Marlon::TicketCategories.ids.first,
      priority: "medium", urgency: 5, status: "open"
    )
    payload = {
      "name" => "Nevaeh Factory Proof #{SecureRandom.hex(5)}",
      "description" => "Automated intent to Studio record with ticket evidence",
      "intent_key" => "production", "start_mode_key" => "blank"
    }
    preview = NevaehIntelligences::Dispatch.call(intent_key: intelligence.intent_key, payload: payload)
    assert_equal "preview", preview.fetch("status")
    assert_equal "Studio::Workers::ProjectCreation", capability.handler
    ticket.update!(status: "in_progress")
    ticket.log!(action: "Nevaeh execution preview", detail: JSON.generate(preview))

    # Inline queue boundary: actual Nevaeh.handle and Gatekeeper authorization
    # still run. The real Studio worker executes, rather than a mocked worker.
    queue = DymondDispatch::Dispatch
    original_open = queue.method(:open)
    deliveries = []
    queue.define_singleton_method(:open) do |**attributes|
      raise "Unexpected handler" unless attributes.fetch(:handler) == "Studio::Workers::ProjectCreation"
      raise "Unexpected action" unless attributes.fetch(:args).first == "create"
      result = Studio::Workers::ProjectCreation.perform(*attributes.fetch(:args))
      deliveries << {"work_item_id" => 777001, "result" => result, "correlation_id" => attributes.fetch(:correlation_id)}
      Struct.new(:id).new(777001)
    end
    begin
      receipt = NevaehIntelligences::Dispatch.call(
        intent_key: intelligence.intent_key, payload: payload,
        actor: Object.new, execute: true
      )
    ensure
      queue.define_singleton_method(:open, original_open)
    end
    assert_equal "dispatched", receipt.fetch("status")
    assert_equal 777001, receipt.fetch("work_item_id")
    assert_equal 1, deliveries.length
    worker_result = deliveries.first.fetch("result")
    project = StudioProject.find(worker_result.fetch("project_id"))
    assert_equal payload.fetch("name"), project.name
    assert_equal 1, project.productions.count
    assert_equal 1, project.studio_scenes.count
    production = project.productions.first
    scene = project.studio_scenes.first
    assert_equal production.id, scene.production_id
    assert worker_result.fetch("project_persisted")

    evidence = {
      "ticket_id" => ticket.id, "capability" => capability.slug,
      "intelligence_id" => intelligence.id,
      "correlation_id" => receipt.fetch("correlation_id"),
      "work_item_id" => receipt.fetch("work_item_id"),
      "project_id" => project.id, "production_id" => production.id,
      "scene_id" => scene.id, "verified" => true,
      "execution_transport" => "test_inline_dispatch_boundary"
    }
    ticket.log!(action: "Nevaeh execution verified", detail: JSON.generate(evidence))
    assert_equal evidence.fetch("project_id"), JSON.parse(ticket.events.order(:id).last.detail).fetch("project_id")
    assert_equal "Nevaeh execution verified", ticket.events.order(:id).last.action
    assert_equal "in_progress", ticket.status # Do not auto-resolve a ticket on simulated queue delivery.
    puts "PROOF_RECEIPT: #{JSON.generate(evidence)}"
  end
end
