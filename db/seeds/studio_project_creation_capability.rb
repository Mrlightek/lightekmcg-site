# frozen_string_literal: true

capability = NevaehCapability.find_or_initialize_by(slug: "studio.project.create")
capability.assign_attributes(
  name: "Studio Project Create",
  domain: "studio",
  description: "Persist a Studio project from a creator-approved intent brief.",
  intent_name: "create_studio_project",
  subject_type: nil,
  handler: "Studio::Workers::ProjectCreation",
  queue: "default",
  priority: 5,
  gatekeeper_capability: "studio.project.create",
  intent_patterns: [],
  expected_outcome: {},
  failure_policy: {"retries" => 1, "escalate" => true},
  realtime: {},
  input_adapter: {},
  metadata: {"surface" => "studio_pwa", "resource" => "project"},
  knowledge_article_ids: [],
  event_types: ["studio.project.create.requested"],
  enabled: true
)
capability.save!
puts "Studio project creation capability seeded."
