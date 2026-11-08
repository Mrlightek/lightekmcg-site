# frozen_string_literal: true
class RegisterNevaehWritingCapabilities < ActiveRecord::Migration[8.0]
  def up
    %w[content_generate writing_profiles].each do |action|
      slug = "studio.workspace.#{action.tr('_', '.')}"
      record = NevaehCapability.find_or_initialize_by(slug: slug)
      next unless record.new_record?
      record.assign_attributes(name: slug.humanize, domain: "studio", intent_name: "studio_workspace_#{action}",
        description: "Use Nevaeh's shared writing service in the authenticated Studio workspace.",
        handler: "Studio::Workers::Workspace", queue: "default", priority: 5, gatekeeper_capability: slug,
        event_types: ["#{slug}.requested"], enabled: true, intent_patterns: [], expected_outcome: {},
        failure_policy: {"retries" => 0, "escalate" => true}, realtime: {}, input_adapter: {},
        metadata: {"surface" => "studio"}, knowledge_article_ids: [])
      record.save!
    end
  end
  def down
    NevaehCapability.where(slug: %w[studio.workspace.content.generate studio.workspace.writing.profiles]).delete_all
  end
end
