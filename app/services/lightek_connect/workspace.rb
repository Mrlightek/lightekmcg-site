module LightekConnect
  class Workspace
    def initialize(connection)
      @connection = connection
      @actor = connection.user
    end
    class Navigation
      include NevaehControlCenterHelper
      def initialize(actor) = @actor = actor
      def current_user = @actor
      def main_app = Rails.application.routes.url_helpers
      def dymond_dash = DymondDash::Engine.routes.url_helpers
      def can?(*args) = Ability.new(@actor).can?(*args)
    end
    def capabilities
      Navigation.new(@actor).nevaeh_navigation_defaults.map { |row| {id: row.fetch("id"), label: row.fetch("label"), path: row.fetch("path")} }
    end
    def site!(id) = LightekSettings::WebsiteIdentity.sites_for(@actor).find(id)
    def snapshot
      {version: 1, agency: {id: @actor.id, name: @actor.account_branding_profile&.brand_name || @actor.email_address},
       clients: User.where(id: Gatekeeper::Hosting::Access.account_ids(@actor)).order(:id).limit(500).map { |u| {id: u.id, name: u.email_address} },
       sites: LightekSettings::WebsiteIdentity.sites_for(@actor).order(:id).limit(500).map { |s| {id: s.id, name: s.name, host: s.host} },
       launches: GatekeeperApplicationLaunch.where(owner_id: Gatekeeper::Hosting::Access.account_ids(@actor)).order(id: :desc).limit(50).map { |l| {id: l.id, name: l.name, domain: l.domain, status: l.status} },
       capabilities: capabilities}
    end
    def rename!(id, name)
      site = site!(id)
      raise ArgumentError, "Website name must contain 1–160 characters" unless name.is_a?(String) && name.strip.length.between?(1, 160)
      if (peer = remote_peer(site))
        data = InstanceTransport.rename!(peer: peer, connection: @connection, name: name)
        Event.record!(@connection, "website_renamed", resource: site.id, details: {remote: true})
        return data.merge("id" => site.id)
      end
      LightekSettings::WebsiteIdentity.rename!(site: site, name: name)
      Event.record!(@connection, "website_renamed", resource: site.id)
      {id: site.id, name: site.reload.name, verified: site.name == name.to_s.strip}
    end
    def management!(id)
      site = site!(id)
      peer = remote_peer(site)
      raise Gatekeeper::Hosting::Access::Denied, "Client instance is unavailable" if peer && !peer.active?
      code = Grant.issue!(connection: @connection, site: site)
      # Always verify the agency browser at the issuer before visiting a client.
      origin = LightekReservations::Federation::Issuer.origin
      {url: "#{origin}/connect/management?code=#{code}", expires_in: 600, external: true}
    end
    def remote_peer(site)
      LightekReservations::Peer.find_by(site: site)
    end
  end
end
