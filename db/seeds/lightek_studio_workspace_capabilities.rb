# frozen_string_literal: true
Studio::Workers::Workspace::ACTIONS.each do |action|
  slug = "studio.workspace.#{action.tr('_', '.')}"
  record = NevaehCapability.find_or_initialize_by(slug: slug)
  record.assign_attributes(name: slug.humanize, domain: "studio", intent_name: "studio_workspace_#{action}",
    description: "Perform #{action.humanize.downcase} in the authenticated creator's Studio workspace.",
    handler: "Studio::Workers::Workspace", queue: "default", priority: 5, gatekeeper_capability: slug,
    event_types: ["#{slug}.requested"], enabled: true, intent_patterns: [], expected_outcome: {},
    failure_policy: { "retries" => 0, "escalate" => true }, realtime: {}, input_adapter: {},
    metadata: { "surface" => "studio" }, knowledge_article_ids: [])
  record.save!
end

# The paid render job authorizes this capability after Stripe confirms payment.
# It is intentionally absent from the generic PWA execution action map.
render_capability = NevaehCapability.find_or_initialize_by(slug: "studio.render.preview")
render_capability.assign_attributes(name: "Studio Render Preview", domain: "studio", intent_name: "render_studio_preview",
  description: "Build a paid Studio scene with Blender and persist its artifacts.", subject_type: "StudioOperation",
  handler: "Studio::Workers::Preview", queue: "studio", priority: 5, gatekeeper_capability: "studio.render.preview",
  event_types: ["studio.render.preview.requested"], enabled: true,
  intent_patterns: [], expected_outcome: { "artifact_kind" => "preview" },
  failure_policy: { "retries" => 0, "escalate" => true }, realtime: {}, input_adapter: {},
  metadata: { "surface" => "studio", "payment_required" => true }, knowledge_article_ids: [])
render_capability.save!
