# frozen_string_literal: true
module LightekMarketing
  # Meta Page tokens do not use a generic refresh-token grant. Check them
  # against Graph and prompt reauthorization when access is no longer valid.
  class MetaConnectionHealth
    class Unavailable < StandardError; end
    def self.check!(connection:)
      raise Unavailable, "Only Meta connections are supported" unless %w[facebook instagram].include?(connection.provider)
      raise Unavailable, "Connection disabled" unless connection.enabled?
      credentials = SocialVault.checkout!(connection: connection)
      token = credentials.fetch("access_token")
      id = connection.provider == "facebook" ? credentials.fetch("page_id") : credentials.fetch("instagram_user_id")
      response = MetaOauth.get!("/#{id}", {fields: "id", access_token: token})
      raise Unavailable, "Provider identity mismatch" unless response["id"].to_s == id.to_s
      {ok: true, checked_at: Time.current}
    rescue MetaOauth::Error, LightekVault::Service::AccessDenied, KeyError => e
      raise Unavailable, "Meta reconnection required: #{e.message}"
    end
  end
end
