module Gatekeeper
  module Compute
    class Provider
      class UnsupportedCapability < StandardError; end
      class ConfigurationError < StandardError; end

      attr_reader :provider, :requested_by, :operation_id

      def initialize(provider:, requested_by: "system", operation_id: nil)
        @provider = provider
        @requested_by = requested_by.to_s
        @operation_id = operation_id
      end

      def regions = unsupported!(:regions)
      def plans = unsupported!(:plans)
      def images = unsupported!(:images)
      def nodes = unsupported!(:nodes)
      def node(_id) = unsupported!(:node)
      def provision_node(**) = unsupported!(:provision_node)
      def reboot_node(_id) = unsupported!(:reboot_node)
      def shutdown_node(_id) = unsupported!(:shutdown_node)
      def start_node(_id) = unsupported!(:start_node)
      def destroy_node(_id) = unsupported!(:destroy_node)
      def set_reverse_dns(ip:, hostname:) = unsupported!(:set_reverse_dns)

      def healthcheck
        { ok: true, provider: provider.slug, adapter: self.class.name }
      end

      protected

      def vault_payload(purpose: "compute_management")
        slug = provider.credential_secret_slug
        raise ConfigurationError, "Provider has no Vault credential configured" if slug.blank?

        LightekVault::Service.checkout!(
          slug: slug,
          consumer: self.class.name,
          purpose: purpose,
          requested_by: requested_by,
          gatekeeper_operation_id: operation_id
        )
      end

      def unsupported!(capability)
        raise UnsupportedCapability, "#{provider.slug} does not implement #{capability}"
      end
    end
  end
end
