module LightekConnect
  class Grant < ApplicationRecord
    self.table_name = "lightek_connect_grants"
    belongs_to :connection
    belongs_to :site, class_name: "DymondSite::Site", optional: true
    belongs_to :authorization_session, class_name: "Session", optional: true
    def self.issue!(connection:, site:, destination: "/dashboard")
      raise Gatekeeper::Hosting::Access::Denied, "Connection revoked" if connection.revoked_at?
      raise ArgumentError, "Invalid destination" unless destination.match?(%r{\A/[a-zA-Z0-9][a-zA-Z0-9/_.-]*\z}) && !destination.split("/").any? { |part| %w[. ..].include?(part) }
      raise Gatekeeper::Hosting::Access::Denied, "Client access removed" if site && !LightekSettings::WebsiteIdentity.sites_for(connection.user).exists?(id: site.id)
      code = SecureRandom.hex(32)
      create!(connection: connection, site: site, destination: destination, code_digest: Connection.digest(code), expires_at: 10.minutes.from_now)
      Event.record!(connection, "management_requested", resource: site&.id)
      code
    end
    def approve!(source)
      with_lock do
        authorize_connection!
        raise Gatekeeper::Hosting::Access::Denied, 'Management grant expired' if consumed_at? || expires_at <= Time.current
        raise Gatekeeper::Hosting::Access::Denied, 'Verify the connected agency account with MFA' unless MfaHandoff.source_verified?(source, connection.user)
        if approved_at?
          raise Gatekeeper::Hosting::Access::Denied, 'Management grant belongs to another session' unless authorization_session_id == source.id
          return self
        end
        update!(authorization_session: source, approved_at: Time.current, expires_at: 60.seconds.from_now,
          delegation_expires_at: [1.hour.from_now, source.mfa_verified_at + 12.hours].min)
        Event.record!(connection, 'management_mfa_verified', resource: site_id, details: {grant_id: id, actor_id: source.user_id})
      end
      self
    end

    def authorize_connection!
      connection.reload
      raise Gatekeeper::Hosting::Access::Denied, 'Connection revoked or agency access removed' if connection.revoked_at? || !connection.user.role.in?(%w[white_label super_admin])
      raise Gatekeeper::Hosting::Access::Denied, 'Client access removed' if site && !LightekSettings::WebsiteIdentity.sites_for(connection.user).exists?(id: site.id)
      raise Gatekeeper::Hosting::Access::Denied, 'Company requires direct sign-in' unless MfaHandoff.allowed_for?(connection.user) && (!site || MfaHandoff.allowed_for?(site.tenant))
    end

    def mfa_context!(consumed: true)
      authorize_connection!
      source = Session.find_by(id: authorization_session_id)
      raise Gatekeeper::Hosting::Access::Denied, 'Management MFA expired or revoked' unless approved_at? &&
        (!consumed || consumed_at?) && delegation_expires_at && delegation_expires_at > Time.current &&
        MfaHandoff.source_verified?(source, connection.user)
      {'version' => 1, 'grant_id' => id, 'connection_id' => connection_id, 'site_id' => site_id,
        'actor' => connection.user.email_address, 'mfa_verified_at' => source.mfa_verified_at.iso8601,
        'expires_at' => delegation_expires_at.iso8601}
    end
    def self.consume!(code:, site:)
      raise Gatekeeper::Hosting::Access::Denied, "Invalid management grant" unless code.to_s.match?(/\A[0-9a-f]{64}\z/)
      grant = find_by!(code_digest: Connection.digest(code), site: site)
      grant.with_lock do
        connection = grant.connection.reload
        raise Gatekeeper::Hosting::Access::Denied, "Management grant expired" if grant.consumed_at? || grant.expires_at <= Time.current || connection.revoked_at? || !connection.user.role.in?(%w[white_label super_admin])
        raise Gatekeeper::Hosting::Access::Denied, "Client access removed" if site && !LightekSettings::WebsiteIdentity.sites_for(connection.user).exists?(id: site.id)
        grant.mfa_context!(consumed: false)
        grant.update!(consumed_at: Time.current)
        Event.record!(connection, "management_opened", resource: site&.id)
      end
      grant
    end
  end
end
