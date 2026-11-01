# frozen_string_literal: true
module NevaehIntelligences
  # Instance-local intake settings on the existing capability. No model provider
  # or credential is required for KB-based execution.
  module EngineeringSettings
    module_function
    def read
      capability = NevaehCapability.find_by(slug: StructuredTicket::CAPABILITY)
      {"sync_enabled" => false}.merge(capability&.metadata.to_h.fetch("github_engineering", {}).slice("sync_enabled", "actor_id"))
    end
  end
end
