# frozen_string_literal: true
module LightekMarketing
  class TiktokTokenRefreshJob < ApplicationJob
    queue_as :default
    def perform(connection_id)
      connection = SocialConnection.find(connection_id)
      return unless connection.enabled? && connection.provider == "tiktok"
      connection.with_lock do
        current = SocialVault.checkout!(connection: connection)
        return if Time.iso8601(current.fetch("expires_at")) > 10.minutes.from_now
        refreshed = TiktokOauth.refresh!(refresh_token: current.fetch("refresh_token"))
        site = connection.site
        actor = site.tenant
        raise TiktokOauth::Error, "No site owner for token refresh" unless actor
        SocialVault.store!(site: site, provider: "tiktok", account: connection.account_label,
          credentials: current.merge(
            "access_token" => refreshed.fetch("access_token"),
            "refresh_token" => refreshed.fetch("refresh_token"),
            "expires_at" => (Time.current + refreshed.fetch("expires_in").to_i.seconds).iso8601),
          actor: actor)
      end
    end
  end
end
