require "securerandom"

module Gatekeeper
  module Compute
    class NodeCredentialService
      Result = Data.define(:secret_slug, :root_password)

      def self.create!(label:, requested_by:)
        root_password = "#{SecureRandom.base64(24)}#{SecureRandom.hex(12)}Aa9!"
        slug = "node-root-#{label.parameterize}-#{SecureRandom.hex(4)}"

        LightekVault::Service.store!(
          name: "Root credential for #{label}",
          slug: slug,
          payload: { "root_password" => root_password },
          secret_type: "password",
          provider: "linode",
          environment: Rails.env,
          purpose: "node_bootstrap",
          access_policy: {
            "consumers" => ["Gatekeeper::Compute::ProvisioningExecutionService"],
            "purposes" => ["provision_node", "node_bootstrap"]
          },
          metadata: {
            "node_label" => label,
            "generated_by" => "Gatekeeper"
          },
          requested_by: requested_by
        )

        Result.new(slug, root_password)
      end
    end
  end
end
