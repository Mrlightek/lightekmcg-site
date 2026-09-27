module Gatekeeper
  module Compute
    class ProviderOnboardingService
      DEFAULT_CAPABILITIES = %w[regions plans images nodes provision_node reboot_node shutdown_node start_node destroy_node set_reverse_dns].index_with(false).freeze

      def self.create!(attributes:, requested_by:)
        attrs = attributes.to_h.stringify_keys
        provider = ComputeProvider.create!(
          name: attrs.fetch("name"),
          slug: attrs.fetch("slug").parameterize(separator: "_"),
          adapter_type: attrs["adapter_type"].presence || "declarative",
          adapter_class: attrs["adapter_class"].presence,
          api_base_url: attrs["api_base_url"].presence,
          documentation_url: attrs["documentation_url"].presence,
          openapi_url: attrs["openapi_url"].presence,
          credential_secret_slug: attrs["credential_secret_slug"].presence,
          status: "draft",
          capabilities: DEFAULT_CAPABILITIES,
          configuration: {},
          metadata: { "created_by" => requested_by, "onboarding_state" => "needs_capability_mapping" }
        )
        record_kb_stub!(provider)
        provider
      end

      def self.record_kb_stub!(provider)
        return unless defined?(Gatekeeper::LessonService)
        Gatekeeper::LessonService.record!(
          key: "GK-PROVIDER-#{provider.slug.upcase}",
          title: "#{provider.name} compute provider onboarding",
          capability: "compute_provider_onboarding",
          symptom: "Lightek needs to manage infrastructure through #{provider.name}.",
          cause: "The provider is new to Gatekeeper and needs capability mappings, authentication policy, smoke tests, and operational procedures.",
          remediation: "Map the provider API to the Gatekeeper Compute Provider contract, store credentials in Lightek Vault, run read-only health checks, then perform approved billable/destructive smoke tests before activation.",
          verification: "Authentication passes; read-only capabilities pass; approved create/reboot/destroy smoke test passes; provider is marked active; all provider secret access is audited through Lightek Vault.",
          metadata: { provider_slug: provider.slug, documentation_url: provider.documentation_url, openapi_url: provider.openapi_url, onboarding_state: "needs_capability_mapping" }
        )
      rescue StandardError => e
        Rails.logger.warn "[ProviderOnboarding] KB stub failed: #{e.class}: #{e.message}"
      end
    end
  end
end
