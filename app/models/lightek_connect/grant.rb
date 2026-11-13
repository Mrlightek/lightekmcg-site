module LightekConnect
  class Grant < ApplicationRecord
    self.table_name = "lightek_connect_grants"
    belongs_to :connection
    belongs_to :site, class_name: "DymondSite::Site", optional: true
    def self.issue!(connection:, site:, destination: "/dashboard")
      raise Gatekeeper::Hosting::Access::Denied, "Connection revoked" if connection.revoked_at?
      raise ArgumentError, "Invalid destination" unless destination.match?(%r{\A/[a-zA-Z0-9][a-zA-Z0-9/_.-]*\z}) && !destination.split("/").any? { |part| %w[. ..].include?(part) }
      raise Gatekeeper::Hosting::Access::Denied, "Client access removed" if site && !LightekSettings::WebsiteIdentity.sites_for(connection.user).exists?(id: site.id)
      code = SecureRandom.hex(32)
      create!(connection: connection, site: site, destination: destination, code_digest: Connection.digest(code), expires_at: 60.seconds.from_now)
      Event.record!(connection, "management_requested", resource: site&.id)
      code
    end
    def self.consume!(code:, site:)
      raise Gatekeeper::Hosting::Access::Denied, "Invalid management grant" unless code.to_s.match?(/\A[0-9a-f]{64}\z/)
      grant = find_by!(code_digest: Connection.digest(code), site: site)
      grant.with_lock do
        connection = grant.connection.reload
        raise Gatekeeper::Hosting::Access::Denied, "Management grant expired" if grant.consumed_at? || grant.expires_at <= Time.current || connection.revoked_at? || !connection.user.role.in?(%w[white_label super_admin])
        raise Gatekeeper::Hosting::Access::Denied, "Client access removed" if site && !LightekSettings::WebsiteIdentity.sites_for(connection.user).exists?(id: site.id)
        grant.update!(consumed_at: Time.current)
        Event.record!(connection, "management_opened", resource: site&.id)
      end
      grant
    end
  end
end
