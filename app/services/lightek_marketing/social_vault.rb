require "digest"
# frozen_string_literal: true
module LightekMarketing
  module SocialVault
    PROVIDERS = {
      "facebook" => %w[page_id access_token],
      "instagram" => %w[instagram_user_id access_token],
      "tiktok" => %w[access_token]
    }.freeze
    def self.slug(site_id:, provider:, account:)
      "lightek-social-#{site_id}-#{provider}-#{Digest::SHA256.hexdigest(account.to_s)[0, 16]}"
    end
    def self.store!(site:, provider:, account:, credentials:, actor:)
      required = PROVIDERS.fetch(provider.to_s)
      data = credentials.to_h.stringify_keys.slice(*required)
      raise ArgumentError, "Missing required provider credentials" unless required.all? { |key| data[key].present? }
      LightekVault::Service.store!(name: "#{provider} / #{account}", slug: slug(site_id: site.id, provider: provider, account: account),
        payload: data, provider: provider, purpose: "social_publish", access_policy: {"consumers" => ["lightek_marketing"], "purposes" => ["social_publish"]},
        requested_by: actor.email_address)
    end
    def self.checkout!(connection:)
      LightekVault::Service.checkout!(slug: connection.credential_key, consumer: "lightek_marketing",
        purpose: "social_publish", requested_by: "lightek_marketing/social_dispatch")
    end
  end
end
