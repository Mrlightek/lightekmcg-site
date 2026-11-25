# frozen_string_literal: true

module LightekConnect
  class AgencyDashboard
    EDIT_DESTINATION = "/dashboard/website/designs"
    INSTANCE_DESTINATION = "/dashboard"
    RELEASE_DESTINATIONS = %w[list stage review deploy rollback].to_h do |action|
      [action, "/internal/agency-website-releases/#{action}"]
    end.freeze

    def self.authorize!(actor, site)
      owner = site.tenant
      unless actor&.role.in?(%w[white_label super_admin]) && LightekPeople::LifecycleAccess.agency_ready?(actor) &&
          owner.is_a?(User) && owner.id != actor.id && owner.role.in?(%w[client white_label]) &&
          LightekPeople::LifecycleAccess.active?(owner) &&
          LightekSettings::WebsiteIdentity.sites_for(actor).exists?(id: site.id)
        raise Gatekeeper::Hosting::Access::Denied, "This client website is outside your agency."
      end
      unless MfaHandoff.allowed_for?(actor) && MfaHandoff.allowed_for?(owner)
        raise Gatekeeper::Hosting::Access::Denied, "Company policy requires direct client sign-in."
      end
      LightekAgency::PackagePolicy.authorize!(owner, "design")
    rescue LightekAgency::PackagePolicy::Denied => error
      raise Gatekeeper::Hosting::Access::Denied, error.message
    end

    def self.connection!(actor)
      actor.with_lock do
        Connection.where(user: actor, platform: "dashboard", revoked_at: nil).first ||
          Connection.create!(user: actor, platform: "dashboard", label: "Agency Dashboard")
      end
    end

    def self.code!(actor:, site:, destination:)
      authorize!(actor, site)
      Grant.issue!(connection: connection!(actor), site: site, destination: destination)
    end

    def self.instance_code!(actor:, site:)
      authorize_instance!(actor, site)
      Grant.issue!(connection: connection!(actor), site: site, destination: INSTANCE_DESTINATION)
    end

    def self.authorize_instance!(actor, site)
      owner = site.tenant
      unless actor&.role == "super_admin" && LightekPeople::LifecycleAccess.active?(actor) &&
          owner.is_a?(User) && owner.id != actor.id && owner.role.in?(%w[client white_label]) &&
          LightekPeople::LifecycleAccess.active?(owner) && MfaHandoff.allowed_for?(actor) && MfaHandoff.allowed_for?(owner)
        raise Gatekeeper::Hosting::Access::Denied, "This instance requires direct sign-in."
      end
      unless LightekReservations::Peer.find_by(site: site, merchant: owner)&.active?
        raise Gatekeeper::Hosting::Access::Denied, "Connect the verified client installation before opening it."
      end
    end

    def self.release_code!(actor:, session:, site:, action:)
      raise Gatekeeper::Hosting::Access::Denied, "Verify your agency authenticator before managing releases." unless MfaHandoff.source_verified?(session, actor)

      code = code!(actor: actor, site: site, destination: RELEASE_DESTINATIONS.fetch(action))
      Grant.find_by!(code_digest: Connection.digest(code)).approve!(session)
      code
    end
  end
end
