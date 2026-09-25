module Gatekeeper
  class CapabilityRegistry
    REGISTRY = {
      "deploy_project" => "Gatekeeper::Capabilities::DeployProject",
      "healthcheck_project" => "Gatekeeper::Capabilities::HealthcheckProject"
    }.freeze

    class UnknownCapability < StandardError; end

    def self.fetch!(name)
      class_name = REGISTRY[name.to_s]
      raise UnknownCapability, "Unregistered Gatekeeper capability: #{name}" unless class_name
      class_name.constantize
    end

    def self.names
      REGISTRY.keys
    end
  end
end
