module LightekPwa
  # The central feed holds references, never remote content bodies or media.
  # Browsers retrieve public posts and media directly from each member's server.
  class Network
    def self.write_destination(user:, site:)
      if user && site && site.tenant != user && site.tenant&.role == 'super_admin' && defined?(MemberBackend)
        backend = MemberBackend.find_by(site: site, user: user)
        return {ready: backend&.ready? || false, manage_url: '/lightek/index.html#/membership', create_url: nil, member_backend: true}
      end
      purchase = Plans.current(user, site)
      return nil unless purchase
      summary = LightekCommerce::Installations.summary(purchase.order)
      {ready: summary[:ready], manage_url: "/my/installations/#{purchase.order_id}",
       create_url: summary[:ready] ? summary[:url] + '/lightek/index.html#/create' : nil}
    end
    def self.require_local_write!(user:, site:)
      destination = write_destination(user: user, site: site)
      return true unless destination
      raise Policy::Denied, destination[:ready] ? 'Publish on your own instance. Open My instance from the PWA.' : 'Your own instance is being set up. Open Membership to follow delivery.'
    end
  end
end
