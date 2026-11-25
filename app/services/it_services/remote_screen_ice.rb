# frozen_string_literal: true

require "openssl"
require "base64"

module ItServices
  class RemoteScreenIce
    def self.for(room, participant_id)
      settings = Rails.application.credentials.dig(:it_remote_support) || {}
      servers = []
      stun = Array(settings[:stun_urls]).grep(/\Astun:/)
      servers << { urls: stun } if stun.any?
      turn = Array(settings[:turn_urls]).grep(/\Aturns?:/)
      secret = settings[:turn_secret].presence
      if turn.any? && secret
        name = "#{room.expires_at.to_i}:support-#{room.id}-#{participant_id}"
        servers << { urls: turn, username: name, credential: Base64.strict_encode64(OpenSSL::HMAC.digest("SHA1", secret, name)) }
      end
      servers
    end
  end
end
