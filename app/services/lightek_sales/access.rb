# frozen_string_literal: true
module LightekSales
  module Access
    def self.prospecting_allowed?(site)
      LightekAgency::PackagePolicy.allowed?(site.tenant, 'marketing') &&
        LightekAgency::PackagePolicy.allowed?(site.tenant, 'commerce')
    end

    def self.sites_for(actor)
      owned = LightekSettings::WebsiteIdentity.sites_for(actor)
      delegated = LightekAgency::SiteMembership.where(user: actor, role: %w[manager marketer]).select(:site_id)
      LightekAgency::Access.sites_for(actor).where(id: owned.select(:id)).or(
        LightekAgency::Access.sites_for(actor).where(id: delegated))
    end

    def self.owners_for(site)
      delegated = LightekAgency::SiteMembership.where(site: site, role: %w[manager marketer]).select(:user_id)
      owner_id = site.tenant_id if site.tenant_type == 'User'
      User.where(access_suspended_at: nil).where(id: delegated).or(User.where(access_suspended_at: nil, id: owner_id)).where(role: %w[super_admin admin white_label client employee])
    end
  end
end
