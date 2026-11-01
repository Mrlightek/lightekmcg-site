# frozen_string_literal: true
module Studio
  module Broadcasting
    class Access
      def self.sites(user)
        LightekPwa::Policy.sites_for(user)
      end
      def self.site(user:, host:, id: nil)
        allowed = sites(user)
        return allowed.find(id) if id.present?
        allowed.find_by(host: host.to_s.downcase) || (allowed.first if allowed.count == 1)
      end
      def self.authorize!(user, site)
        LightekPwa::Policy.new(user: user, site: site).authorize_admin!("studio")
      end
    end
  end
end
