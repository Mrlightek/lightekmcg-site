# frozen_string_literal: true
module LightekPwa
  class SiteContext
    def self.resolve(host)
      DymondSite::Site.find_by!(host: host.to_s.downcase)
    end
  end
end
