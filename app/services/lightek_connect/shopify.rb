require "jwt"
require "active_support/security_utils"
require "openssl"
require "base64"
module LightekConnect
  module Shopify
    class Invalid < StandardError; end
    def self.identity!(authorization)
      token = authorization.to_s.delete_prefix("Bearer ")
      secret = ENV.fetch("LIGHTEK_SHOPIFY_CLIENT_SECRET")
      raise Invalid if secret.blank? || ENV.fetch("LIGHTEK_SHOPIFY_CLIENT_ID").blank?
      claims, = JWT.decode(token, secret, true, algorithm: "HS256", verify_aud: true,
        aud: ENV.fetch("LIGHTEK_SHOPIFY_CLIENT_ID"), verify_not_before: true)
      dest = claims["dest"].to_s
      raise Invalid unless dest.match?(%r{\Ahttps://[a-z0-9][a-z0-9-]*\.myshopify\.com\z}) && claims["iss"] == "#{dest}/admin"
      raise Invalid unless claims["sub"].to_s.match?(/\A[0-9]+\z/) && claims["exp"].is_a?(Numeric) && claims["nbf"].is_a?(Numeric)
      "#{URI.parse(dest).host}:#{claims.fetch('sub')}"
    rescue JWT::DecodeError, KeyError, URI::InvalidURIError
      raise Invalid, "Invalid Shopify session"
    end
    def self.webhook_valid?(body, signature)
      return false if ENV.fetch("LIGHTEK_SHOPIFY_CLIENT_SECRET").blank?
      expected = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", ENV.fetch("LIGHTEK_SHOPIFY_CLIENT_SECRET"), body))
      ActiveSupport::SecurityUtils.secure_compare(expected, signature.to_s)
    rescue KeyError
      false
    end
  end
end
