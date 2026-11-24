# frozen_string_literal: true

module Gatekeeper
  module Compute
    class StagingRequests
      class Invalid < StandardError; end

      PROVIDER_SLUG = "linode"
      LEGACY_PROVIDER_SLUG = "linode-staging"
      LINODE_CONSUMER = "Gatekeeper::Compute::Providers::LinodeAdapter"
      PLAN = "g6-standard-2"
      IMAGE = "linode/ubuntu24.04"
      BUDGET_CENTS = 2400
      METADATA_KEY = "staging_provisioning"
      VAULT_POLICIES = {
        "compute" => [LINODE_CONSUMER, "compute_management"],
        "dns" => ["Godaddy::DnsService", "dns_management"],
        "owner" => ["Gatekeeper::WebsiteDeployment", "website_deploy"]
      }.freeze

      def self.staging_provider?(provider)
        provider.slug == LEGACY_PROVIDER_SLUG && provider.adapter_type == "builtin" &&
          provider.adapter_class == LINODE_CONSUMER
      end

      def self.prepare!(actor:, hostname:, budget_cents:, hours:, settings: nil)
        WebsiteDeployment.authorize!(actor)
        raise Invalid, "Active super administrator access is required" unless LightekPeople::LifecycleAccess.active?(actor)
        raise Invalid, "Budget must be between 1 and 2400 cents" unless (1..BUDGET_CENTS).cover?(budget_cents)
        raise Invalid, "Lifetime must be between 4 and 168 hours" unless (4..168).cover?(hours)

        unless hostname.match?(/\Abatch-d-[a-z0-9]+(?:-[a-z0-9]+)*\.staging\.(?:[a-z0-9-]+\.)+[a-z]{2,}\z/)
          raise Invalid, "Enter a batch-d hostname under staging on a managed domain"
        end
        zone, = WebsiteDnsPublication.target_for!(hostname: hostname)

        owner_email = setting!("OWNER", settings)
        owner = staging_owners.find { |user| user.email_address == owner_email }
        raise Invalid, "Select an active synthetic staging owner" unless owner

        provider = staging_provider
        raise Invalid, "The existing Linode provider must be active and healthy" unless provider

        compute_slug = compute_credential(settings)
        raise Invalid, "Select a separate staging Linode Vault entry" unless eligible_provider?(provider, compute_slug)

        vault = { "compute" => compute_slug, "dns" => setting!("DNS_VAULT", settings),
          "owner" => setting!("OWNER_VAULT", settings) }
        validate_vault!(vault)
        region = setting!("REGION", settings)
        certificate_email = setting!("CERTIFICATE_EMAIL", settings)
        label = hostname.split(".").first
        raise Invalid, "Staging node label is too long" if label.length > 63

        adapter = linode_adapter(provider, vault.fetch("compute"), requested_by: actor.email_address)
        catalog = LinodeCatalogService.call(provider: provider, requested_by: actor.email_address, region: region, adapter: adapter)
        plan = approved_plan!(catalog, region, budget_cents)
        config = WebsiteDeployment.configuration(owner: owner, domain: hostname, site_name: "Lightek MSP staging",
          headline: "Release acceptance", description: "Synthetic acceptance tenant",
          certificate_email: certificate_email, credential_slug: vault.fetch("owner")).except("branding")

        provider.with_lock do
          raise Invalid, "Staging provider changed during the quote" unless eligible_provider?(provider, vault["compute"])
          if ProvisioningRequest.where(node_label: label).where(destroyed_at: nil).where.not(execution_status: "cancelled").exists? ||
              GatekeeperNode.where(name: label).where.not(status: "decommissioned").exists?
            raise Invalid, "A request or node already holds this staging label. Review it before preparing another."
          end

          request = ProvisioningRequest.create!(owner: owner, compute_provider: provider, requested_node_count: 1,
            selected_region: region, selected_plan: PLAN, selected_image: IMAGE, node_label: label,
            estimated_monthly_cost_cents: plan.fetch("monthly_cents"), approval_status: "pending",
            execution_status: "awaiting_approval", metadata: { "release_assurance_staging" => true,
              METADATA_KEY => { "hostname" => hostname, "zone" => zone, "budget_cents" => budget_cents,
                "expires_at" => hours.hours.from_now.iso8601, "vault" => vault, "owner_id" => owner.id,
                "provider_id" => provider.id, "region" => region, "estimate_cents" => plan.fetch("monthly_cents"),
                "audit" => [event(actor, "prepared")] } })
          WebsiteDeployment.register!(actor: actor, record: request, config: config)
          request
        end
      rescue WebsiteDnsPublication::NotConfigured
        raise Invalid, "This hostname has no managed GoDaddy zone in Dashboard → Network & Domains"
      rescue LinodeCatalogService::WrongProvider, LinodeCatalogService::NoMatchingPlan
        raise Invalid, "The staging Linode catalog is unavailable"
      end

      def self.validate!(request, retiring: false)
        data = request.metadata.to_h.fetch(METADATA_KEY)
        owner = request.owner
        valid = (retiring || Time.iso8601(data.fetch("expires_at")).future?) &&
          owner.is_a?(User) && owner.role == "client" && owner.email_address.match?(/\Astaging-[a-z0-9-]+@example\.test\z/) &&
          (retiring || LightekPeople::LifecycleAccess.active?(owner)) && request.owner_id == data["owner_id"] &&
          request.compute_provider_id == data["provider_id"] &&
          eligible_provider?(request.compute_provider, data.fetch("vault").fetch("compute")) &&
          request.subscription_id.nil? && request.requested_node_count == 1 && request.selected_region == data["region"] &&
          request.selected_plan == PLAN && request.selected_image == IMAGE &&
          request.node_label == data.fetch("hostname").split(".").first &&
          request.estimated_monthly_cost_cents == data["estimate_cents"] &&
          (1..BUDGET_CENTS).cover?(data["budget_cents"]) &&
          (1..data["budget_cents"]).cover?(request.estimated_monthly_cost_cents)
        raise Invalid, "The staging request expired or its approved inputs changed" unless valid

        validate_vault!(data.fetch("vault"), include_owner: !retiring)
        data
      rescue KeyError, ArgumentError
        raise Invalid, "The staging request has an invalid binding"
      end

      def self.audit_metadata(request, actor, disposition)
        data = request.metadata.fetch(METADATA_KEY)
        request.metadata.merge(METADATA_KEY => data.merge("audit" => data.fetch("audit") + [event(actor, disposition)]))
      end

      def self.event(actor, disposition)
        { "action" => disposition, "actor_id" => actor.id, "at" => Time.current.iso8601 }
      end

      def self.eligible_provider?(provider, slug)
        return false unless provider&.status == "active" && provider.health_status == "healthy"
        return provider.credential_secret_slug == slug if staging_provider?(provider)

        shared_provider?(provider) && provider.credential_secret_slug != slug
      end

      def self.approved_plan!(catalog, region, budget_cents)
        plan = catalog.fetch("plans").find { |entry| entry["id"] == PLAN }
        unless catalog.fetch("regions").any? { |entry| entry["id"] == region && entry["status"] == "ok" } &&
            catalog.fetch("images").any? { |entry| entry["id"] == IMAGE } && plan &&
            plan["vcpus"].to_i >= 2 && plan["memory"].to_i >= 4096 && plan["disk"].to_i >= 65_536 &&
            (1..budget_cents).cover?(plan["monthly_cents"])
          raise Invalid, "Live staging quote exceeds the cap or the required plan, region or image is unavailable"
        end
        plan
      end

      def self.staging_owners
        User.where(role: "client").where("email_address LIKE ?", "staging-%@example.test").order(:email_address).select do |owner|
          owner.email_address.match?(/\Astaging-[a-z0-9-]+@example\.test\z/) && LightekPeople::LifecycleAccess.active?(owner)
        end
      end

      def self.staging_provider
        provider = ComputeProvider.find_by(slug: PROVIDER_SLUG, status: "active", health_status: "healthy")
        provider if shared_provider?(provider)
      end

      def self.shared_provider?(provider)
        provider&.slug == PROVIDER_SLUG && provider.adapter_type == "builtin" &&
          [nil, LINODE_CONSUMER].include?(provider.adapter_class.presence)
      end

      def self.compute_credential(settings)
        return setting!("COMPUTE_VAULT", settings) if settings

        ENV["LIGHTEK_RELEASE_ASSURANCE_COMPUTE_VAULT"].presence ||
          vault_choices.fetch("compute").sole
      rescue ActiveSupport::EnumerableCoreExt::SoleItemExpectedError
        raise Invalid, "Select the staging Linode Vault entry"
      end

      def self.adapter_for!(request, requested_by:, operation_id: nil)
        data = request.metadata.fetch(METADATA_KEY)
        slug = data.fetch("vault").fetch("compute")
        provider = request.compute_provider
        unless request.compute_provider_id == data.fetch("provider_id") && eligible_provider?(provider, slug)
          raise Invalid, "Staging Linode provider or Vault binding changed"
        end

        secret = LightekVault::Secret.active.find_by(slug: slug, environment: "staging")
        raise Invalid, "Staging Linode Vault entry is unavailable" unless usable_vault?(secret, VAULT_POLICIES.fetch("compute"))

        linode_adapter(provider, slug, requested_by: requested_by, operation_id: operation_id)
      rescue KeyError
        raise Invalid, "Missing staging Linode binding"
      end

      def self.linode_adapter(provider, slug, requested_by:, operation_id: nil)
        Providers::LinodeAdapter.new(provider: provider, credential_slug: slug,
          requested_by: requested_by, operation_id: operation_id)
      end

      def self.vault_choices
        secrets = LightekVault::Secret.active.where(environment: "staging").order(:slug)
        VAULT_POLICIES.transform_values do |policy|
          secrets.select { |secret| usable_vault?(secret, policy) }.map(&:slug)
        end
      end

      def self.validate_vault!(vault, include_owner: true)
        keys = include_owner ? VAULT_POLICIES.keys : %w[compute dns]
        keys.each do |key|
          secret = LightekVault::Secret.active.find_by(slug: vault.fetch(key), environment: "staging")
          unless usable_vault?(secret, VAULT_POLICIES.fetch(key))
            raise Invalid, "Configure the staging-only #{key} Vault reference with its explicit access policy"
          end
        end
      end

      def self.usable_vault?(secret, (consumer, purpose))
        return false unless secret&.usable? && secret.slug.start_with?("staging-")

        policy = secret.access_policy.to_h
        Array(policy["consumers"]).include?(consumer) && Array(policy["purposes"]).include?(purpose)
      end

      def self.setting!(key, settings)
        if settings
          settings[key].presence || raise(Invalid, "Enter or select the staging #{key.downcase.tr('_', ' ')}")
        else
          ENV["LIGHTEK_RELEASE_ASSURANCE_#{key}"].presence ||
            raise(Invalid, "The staging control plane is missing its #{key.downcase.tr('_', ' ')} setting")
        end
      end
      private_class_method :event, :approved_plan!, :eligible_provider?, :validate_vault!, :setting!
    end
  end
end
