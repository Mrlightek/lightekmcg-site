module LightekGrowth
  module Audits
    class Access
      def initialize(actor:, site:)
        @actor, @site = actor, site
        read!
      end
      def read!
        @actor.reload
        LightekSales::Access.sites_for(@actor).find(@site.id)
        LightekAgency::PackagePolicy.authorize!(@site.tenant, 'marketing')
      end
      def write!
        read!
        LightekSettings::WebsiteIdentity.sites_for(@actor).find(@site.id)
        LightekAgency::PackagePolicy.authorize!(@site.tenant, 'design')
      end
    end
  end
end
