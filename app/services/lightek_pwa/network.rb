module LightekPwa
  # The central feed holds references, never remote content bodies or media.
  # Browsers retrieve public posts and media directly from each member's server.
  class Network
    STUDIO_READS = %w[studio.pwa.bootstrap studio.workspace.assets.list studio.workspace.operations.list
      studio.workspace.look.status studio.workspace.ai.status studio.workspace.ai.setup.status studio.workspace.ai.jobs
      studio.workspace.writing.profiles studio.workspace.shots.list studio.workspace.starter.scene.status
      studio.workspace.performance.analysis studio.workspace.blender.runtime.status].freeze
    def self.require_studio_write!(user:, site:, capability:)
      return true if STUDIO_READS.include?(capability)
      require_local_write!(user: user, site: site)
    end
    def self.write_destination(user:, site:)
      purchase = Plans.current(user, site)
      if user && site && user.role != 'super_admin' && Policy.platform_operator(site).present? && defined?(MemberBackend)
        backend = MemberBackend.find_by(site: site, user: user)
        return {ready: backend&.ready? || false, manage_url: '/lightek/index.html#/membership', create_url: nil, member_backend: true} if backend || !purchase
      end
      return nil unless purchase
      summary = LightekCommerce::Installations.summary(purchase.order)
      {ready: summary[:ready], manage_url: "/my/installations/#{purchase.order_id}",
       create_url: summary[:ready] ? summary[:url] + '/lightek/index.html#/create' : nil}
    end
    def self.require_local_write!(user:, site:)
      if site&.manifest.to_h.dig('pwa_member', 'hosting') == 'shared_account'
        raise Policy::Denied, 'Publish from your own shared hosting account' unless user && site.tenant == user
      end
      destination = write_destination(user: user, site: site)
      return true unless destination
      raise Policy::Denied, destination[:ready] ? 'Publish on your own instance. Open My instance from the PWA.' : 'Your own instance is being set up. Open Membership to follow delivery.'
    end
  end
end
