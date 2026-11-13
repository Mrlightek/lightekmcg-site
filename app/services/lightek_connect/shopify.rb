require "jwt"
require "active_support/security_utils"
require "openssl"
require "base64"
module LightekConnect
  module Shopify
    class Invalid < StandardError; end
    def self.identity!(authorization)
      token = authorization.to_s.delete_prefix("Bearer ")
      claims = ShopifyCredentials.with_credentials do |credentials|
        JWT.decode(token, credentials.fetch("client_secret"), true, algorithm: "HS256", verify_aud: true,
          aud: credentials.fetch("client_id"), verify_not_before: true).first
      end
      dest = claims["dest"].to_s
      raise Invalid unless dest.match?(%r{\Ahttps://[a-z0-9][a-z0-9-]*\.myshopify\.com\z}) && claims["iss"] == "#{dest}/admin"
      raise Invalid unless claims["sub"].to_s.match?(/\A[0-9]+\z/) && claims["exp"].is_a?(Numeric) && claims["nbf"].is_a?(Numeric)
      "#{URI.parse(dest).host}:#{claims.fetch('sub')}"
    rescue JWT::DecodeError, KeyError, URI::InvalidURIError
      raise Invalid, "Invalid Shopify session"
    end
    def self.webhook_valid?(body, signature)
      ShopifyCredentials.with_credentials do |credentials|
        expected = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", credentials.fetch("client_secret"), body))
        ActiveSupport::SecurityUtils.secure_compare(expected, signature.to_s)
      end
    rescue KeyError
      false
    end
  end
end
