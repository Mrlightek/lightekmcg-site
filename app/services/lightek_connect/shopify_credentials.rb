module LightekConnect
  class ShopifyCredentials
    class Unavailable < StandardError; end
    SLUG = "shopify-connect".freeze
    PURPOSE = "shopify_connect".freeze
    CONSUMER = name.freeze

    def self.store!(actor:, client_id:, client_secret:)
      raise Gatekeeper::Hosting::Access::Denied, "A super administrator configures the Shopify app" unless Gatekeeper::Hosting::Access.super_admin?(actor)
      id = client_id.to_s.strip
      secret = client_secret.to_s
      raise ArgumentError, "Enter a valid Shopify Client ID" unless id.match?(/\A[a-zA-Z0-9_-]{8,200}\z/)
      raise ArgumentError, "Enter the Shopify Client secret" unless secret.length.between?(8, 4096) && !secret.match?(/\s/)
      begin
        LightekVault::Service.store!(name: "Lightek Connect · Shopify app", slug: SLUG, provider: "shopify",
          purpose: PURPOSE, payload: {"client_id" => id, "client_secret" => secret},
          metadata: {"client_id" => id},
          access_policy: {"consumers" => [CONSUMER], "purposes" => [PURPOSE]}, requested_by: actor.email_address)
      rescue StandardError
        raise Unavailable, "Shopify credentials could not be saved. Check Vault access in Dashboard."
      end
    end

    def self.status
      record = LightekVault::Secret.find_by(slug: SLUG)
      {stored: record&.usable? == true, client_id: record&.metadata.to_h["client_id"]}
    end

    def self.checkout!
      LightekVault::Service.checkout!(slug: SLUG, consumer: CONSUMER, purpose: PURPOSE, requested_by: "shopify-connect")
    rescue StandardError
      # Missing, disabled, expired, inaccessible and undecryptable credentials all fail closed.
      raise Unavailable, "Shopify credentials are unavailable. Configure Shopify in Dashboard → Lightek Connect and verify Vault access."
    end

    def self.with_credentials
      payload = checkout!
      unless payload.is_a?(Hash) && payload["client_id"].is_a?(String) && payload["client_id"].present? &&
          payload["client_secret"].is_a?(String) && payload["client_secret"].present?
        raise Unavailable, "The Shopify Vault entry needs client_id and client_secret fields."
      end
      yield payload
    ensure
      payload&.each_value { |value| value.clear if value.is_a?(String) && !value.frozen? } if payload.is_a?(Hash)
    end

    def self.client_id
      with_credentials { |payload| payload.fetch("client_id").dup }
    end
  end
end
