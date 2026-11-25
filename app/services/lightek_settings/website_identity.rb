# frozen_string_literal: true
module LightekSettings
  class WebsiteIdentity
    class RemovalDenied < StandardError; end

    OVERVIEW_HIDDEN_KEY = "dashboard_overview_hidden"
    MANAGED_SITE_KEYS = %w[agency_demo hosted_application_key lightek_website_bootstrap network_ledger pwa_member pwa_pool lightek_reservation_federation].freeze

    def self.sites_for(user)
      return DymondSite::Site.none if defined?(LightekPeople::LifecycleAccess) && !LightekPeople::LifecycleAccess.active?(user)
      if user&.role == 'client'
        return available_demo_scope(DymondSite::Site.where(tenant: user).or(DymondSite::Site.where(id: LightekReservations::Peer.where(merchant: user).select(:site_id))))
      end
      return available_demo_scope(DymondSite::Site.where(tenant_type: "User", tenant_id: user.managed_account_ids)) if user&.role == "white_label"
      return DymondSite::Site.none unless user&.role.to_s.in?(%w[admin super_admin])
      return DymondSite::Site.all if user.role == "super_admin"
      DymondSite::Site.where(tenant: user)
    end

    def self.available_demo_scope(scope)
      return scope unless defined?(LightekAgency::Demo) && LightekAgency::Demo.table_exists?
      scope.where.not(id: LightekAgency::Demos.hidden_site_ids)
    end

    def self.overview_sites_for(user)
      sites = sites_for(user)
      return sites unless user&.role == "super_admin"

      sites.where("CAST(manifest -> ? AS text) IS DISTINCT FROM 'true'", OVERVIEW_HIDDEN_KEY)
    end

    def self.overview_hidden?(site)
      site.manifest.to_h[OVERVIEW_HIDDEN_KEY] == true
    end

    def self.set_overview_hidden!(site:, hidden:, request_host:)
      site.with_lock do
        guard_primary!(site, request_host) if hidden
        manifest = site.manifest.to_h.except(OVERVIEW_HIDDEN_KEY)
        manifest[OVERVIEW_HIDDEN_KEY] = true if hidden
        site.update!(manifest: manifest)
      end
    end

    def self.delete!(site:, confirmation:, request_host:)
      site.with_lock do
        guard_primary!(site, request_host)
        unless confirmation == site.host
          raise RemovalDenied, "Enter the exact website hostname to confirm deletion."
        end

        reason = deletion_blocker(site)
        raise RemovalDenied, reason if reason

        site.destroy!
      end
    rescue ActiveRecord::InvalidForeignKey, ActiveRecord::RecordNotDestroyed, ActiveRecord::DeleteRestrictionError
      raise RemovalDenied, "This website has linked records and could not be deleted. You can hide it from Overview."
    end

    def self.deletion_blocker(site)
      if MANAGED_SITE_KEYS.any? { |key| site.manifest.to_h[key].present? } ||
          GatekeeperApplicationLaunch.where(domain: site.host).where.not(status: "deleted").exists? ||
          GatekeeperNode.where("jsonb_exists(metadata -> 'website_deployments', ?)", site.host).exists? ||
          LightekPwa::MemberBackend.exists?(hostname: site.host) ||
          LightekReservations::Peer.exists?(site_id: site.id)
        return "This website is managed by hosting, a member backend, or a demo. You can hide it from Overview."
      end

      if LightekAgency::DemoSetting.exists?(public_site_id: site.id) ||
          LightekCommerce::Order.exists?(site_id: site.id)
        "This website has demo settings or commerce orders. You can hide it from Overview."
      end
    end

    def self.primary?(site, request_host)
      configured_host = Rails.application.config.action_mailer.default_url_options&.fetch(:host, nil)
      [request_host, configured_host].compact.any? { |host| site.host.casecmp?(host) }
    end

    def self.guard_primary!(site, request_host)
      raise RemovalDenied, "The primary website is protected." if primary?(site, request_host)
    end
    private_class_method :guard_primary!

    def self.rename!(site:, name:)
      site.with_lock do
        previous_name = site.name
        site.update!(name: name.to_s.strip)
        site.pages.each do |page|
          page.sections.where(kind: "hero").each do |section|
            data = section.data.to_h
            next unless data["eyebrow"].to_s.casecmp?(previous_name.to_s)
            section.update!(data: data.merge("eyebrow" => site.name))
          end
        end
      end
      site
    end
  end
end
