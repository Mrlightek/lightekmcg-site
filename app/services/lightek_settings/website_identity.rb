# frozen_string_literal: true
module LightekSettings
  class WebsiteIdentity
    def self.sites_for(user)
      return DymondSite::Site.none unless user&.role.to_s.in?(%w[admin super_admin])
      return DymondSite::Site.all if user.role == "super_admin"
      DymondSite::Site.where(tenant: user)
    end

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
