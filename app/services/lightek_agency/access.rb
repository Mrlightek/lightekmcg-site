# frozen_string_literal: true
module LightekAgency
  module Access
    def self.sites_for(user)
      owned = LightekSettings::WebsiteIdentity.sites_for(user)
      return owned if user&.role == "super_admin"
      delegated_ids = SiteMembership.where(user: user).select(:site_id)
      DymondSite::Site.where(id: owned.select(:id)).or(DymondSite::Site.where(id: delegated_ids))
    end
    def self.manage_members?(user, site)
      LightekSettings::WebsiteIdentity.sites_for(user).exists?(id: site.id)
    end
  end
end
