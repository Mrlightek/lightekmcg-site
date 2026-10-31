module Gatekeeper
  module Hosting
    class SiteRouting
      RESERVED = %w[dashboard portal employee sessions session sign_in sign_up sign_out passwords registrations up cable api gatekeeper billing studio site community communities posts profiles marketplace commerce susu connect kb catalog booking lightek assets jobs system_jobs].freeze
      def self.match?(host)
        site = DymondSite::Site.find_by(host: host.to_s.downcase)
        site && site.manifest.to_h["hosted_application_key"].present?
      end

      def self.page_match?(request)
        slug = request.path.split("/")[1].to_s.downcase
        return false if RESERVED.include?(slug)
        site = DymondSite::Site.find_by(host: request.host.to_s.downcase)
        site && site.manifest.to_h["hosted_application_key"].present? && site.pages.published.exists?(slug: slug)
      end
    end
  end
end
