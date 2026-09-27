module Gatekeeper
  module Compute
    class ProvisioningExecutionService
      class NotExecutable < StandardError; end
      class UnsupportedProvider < StandardError; end
      class ProviderResponseError < StandardError; end

      def self.call(request:, requested_by:)
        new(request:, requested_by:).call
      end

      def initialize(request:, requested_by:)
        @request = request
        @requested_by = requested_by.to_s
      end

      def call
        validate!

        control_node = GatekeeperNode.order(:id).first ||
          raise(NotExecutable, "No Gatekeeper control node is registered")

        operation = GatekeeperOperation.create!(
          gatekeeper_node: control_node,
          capability: "provision_compute_node",
          requested_by: requested_by,
          status: "running",
          parameters: operation_parameters,
          started_at: Time.current
        )

        request.update!(gatekeeper_operation: operation, execution_status: "provisioning")

        credential = NodeCredentialService.create!(
          label: request.node_label,
          requested_by: requested_by
        )

        begin
          adapter = request.compute_provider.adapter(
            requested_by: requested_by,
            operation_id: operation.id
          )

          provider_node = adapter.provision_node(
            label: request.node_label,
            region: request.selected_region,
            plan: request.selected_plan,
            image: request.selected_image,
            root_password: credential.root_password,
            tags: [
              "lightek-managed",
              "gatekeeper",
              "provisioning-request-#{request.id}"
            ]
          )

          node = create_gatekeeper_node!(provider_node, credential.secret_slug)

          operation.update!(
            status: "succeeded",
            result: sanitize_provider_result(provider_node).merge("gatekeeper_node_id" => node.id),
            completed_at: Time.current,
            exit_status: 0
          )

          request.update!(
            gatekeeper_node: node,
            execution_status: "succeeded",
            provisioned_at: Time.current,
            metadata: request.metadata.to_h.merge(
              "node_credential_secret_slug" => credential.secret_slug,
              "provider_resource_id" => node.provider_resource_id
            )
          )

          node
        rescue StandardError => e
          operation.update!(
            status: "failed",
            error_class: e.class.name,
            error_message: e.message,
            completed_at: Time.current,
            exit_status: 1
          )

          request.update!(
            execution_status: "failed",
            error_class: e.class.name,
            error_message: e.message
          )

          raise
        ensure
          credential.root_password.clear if credential&.root_password.respond_to?(:clear)
        end
      end

      private

      attr_reader :request, :requested_by

      def validate!
        raise NotExecutable, "Provisioning request is not approved and ready" unless request.executable?
        raise UnsupportedProvider, "First billable execution pass supports Linode only" unless request.compute_provider.slug == "linode"
        raise NotExecutable, "Provider must be active" unless request.compute_provider.status == "active"
        raise NotExecutable, "Provider must be healthy" unless request.compute_provider.health_status == "healthy"
      end

      def operation_parameters
        {
          provisioning_request_id: request.id,
          provider: request.compute_provider.slug,
          region: request.selected_region,
          plan: request.selected_plan,
          image: request.selected_image,
          label: request.node_label,
          estimated_monthly_cost_cents: request.estimated_monthly_cost_cents
        }
      end

      def create_gatekeeper_node!(provider_node, credential_slug)
        resource_id = provider_node["id"] ||
          raise(ProviderResponseError, "Linode response did not include id")

        ipv4 = Array(provider_node["ipv4"]).first
        ipv6 = provider_node["ipv6"].to_s.split("/").first.presence

        raise ProviderResponseError, "Linode response did not include IPv4" if ipv4.blank?

        GatekeeperNode.create!(
          name: request.node_label,
          hostname: request.node_label,
          ip_address: ipv4,
          public_ipv6: ipv6,
          ssh_user: "root",
          ssh_port: 22,
          provider: request.compute_provider.name,
          provider_id: resource_id.to_s,
          provider_resource_id: resource_id.to_s,
          compute_provider: request.compute_provider,
          provisioning_profile: request.provisioning_profile,
          compute_policy: request.compute_policy,
          owner: request.owner,
          purpose: request.provisioning_profile&.purpose || "test",
          region: provider_node["region"].presence || request.selected_region,
          plan: provider_node["type"].presence || request.selected_plan,
          image: request.selected_image,
          status: normalize_status(provider_node["status"]),
          estimated_monthly_cost_cents: request.estimated_monthly_cost_cents,
          metadata: {
            "managed_by" => "gatekeeper",
            "provisioning_request_id" => request.id,
            "node_credential_secret_slug" => credential_slug,
            "provider_label" => provider_node["label"],
            "provider_created" => provider_node["created"]
          }.compact
        )
      end

      def normalize_status(value)
        case value.to_s
        when "running" then "healthy"
        when "offline" then "degraded"
        when "provisioning", "booting" then "provisioning"
        else "unknown"
        end
      end

      def sanitize_provider_result(provider_node)
        provider_node.slice("id", "label", "status", "region", "type", "ipv4", "ipv6", "created")
      end
    end
  end
end
