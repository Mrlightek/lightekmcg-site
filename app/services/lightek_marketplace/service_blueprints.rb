# frozen_string_literal: true
module LightekMarketplace
  # Stable, versioned fulfillment contract shared by the product editor and
  # delivery. A category organizes products; a blueprint specifies execution.
  module ServiceBlueprints
    Blueprint = Data.define(:key, :name, :delivery, :description, :requires_subscription, :activation)
    DEFINITIONS = [
      Blueprint.new("website", "Managed website", "website",
        "Create a customer-owned Dymond Site on existing infrastructure. Domain and TLS activation remain pending.", true, "site_created"),
      Blueprint.new("application_access", "Existing Lightek application", "access",
        "Grant access to an approved application connection.", false, "access_granted"),
      Blueprint.new("compute_instance", "Managed compute instance", "compute",
        "Create a Gatekeeper provisioning request under an active infrastructure subscription. Provider approval and provisioning follow existing policy.", true, "provisioning_request"),
      Blueprint.new("managed_work", "Managed fulfillment", "manual",
        "Open a tracked operational ticket for team delivery.", false, "work_requested")
    ].index_by(&:key).freeze

    def self.all = DEFINITIONS.values
    def self.find(key) = DEFINITIONS[key.to_s]
    def self.for_delivery(delivery)
      DEFINITIONS.values.find { |blueprint| blueprint.delivery == delivery.to_s }
    end
  end
end
