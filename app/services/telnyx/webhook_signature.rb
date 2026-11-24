# frozen_string_literal: true

require "base64"
require "ed25519"

module Telnyx
  class WebhookSignature
    def self.valid?(timestamp:, signature:, body:, now: Time.now.to_i)
      return false unless /\A\d{10}\z/.match?(timestamp.to_s) && (now - timestamp.to_i).abs <= 300
      return false unless signature.is_a?(String) && signature.bytesize == 88

      key = Base64.strict_decode64(ENV.fetch("TELNYX_PUBLIC_KEY"))
      raw_signature = Base64.strict_decode64(signature)
      return false unless key.bytesize == 32 && raw_signature.bytesize == 64

      Ed25519::VerifyKey.new(key).verify(raw_signature, "#{timestamp}|".b + body.b)
    rescue ArgumentError, Ed25519::VerifyError
      false
    end
  end
end
