# frozen_string_literal: true
require "uri"
module Studio
  module Live
    class Destination
      class Unavailable < StandardError; end
      CONSUMER = "Studio::Live::Destination"
      PURPOSE = "live_broadcast"

      def self.slug(user) = "studio-live-#{user.id}-tiktok"
      def self.configured?(user)
        LightekVault::Secret.where(slug: slug(user), status: "active").where("expires_at IS NULL OR expires_at > ?", Time.current).exists?
      end
      def self.validate!(server_url, stream_key)
        uri = URI.parse(server_url.to_s.strip)
        host = uri.host.to_s.downcase
        valid_host = %w[tiktok.com tiktokv.com tiktokcdn.com tiktokcdn-us.com ttlivecdn.com].any? { |suffix| host.end_with?(".#{suffix}") }
        raise Unavailable, "Use the RTMP or RTMPS server URL supplied by TikTok." unless %w[rtmp rtmps].include?(uri.scheme) && valid_host && uri.userinfo.nil? && uri.fragment.nil? && uri.query.nil? && [443, 1935].include?(uri.port || (uri.scheme == "rtmps" ? 443 : 1935))
        key = stream_key.to_s.strip
        raise Unavailable, "Enter the stream key supplied by TikTok." if key.empty? || key.bytesize > 2048 || key.match?(/[\s\x00-\x1f]/)
        [uri.to_s.sub(%r{/+\z}, "") + "/", key]
      rescue URI::InvalidURIError
        raise Unavailable, "Use the server URL supplied by TikTok."
      end
      def self.save!(user:, server_url:, stream_key:)
        ::Gatekeeper::StudioLivePolicy.authorize!(user: user, configure: true)
        server, key = validate!(server_url, stream_key)
        LightekVault::Service.store!(name: "TikTok LIVE · #{user.id}", slug: slug(user), payload: {"server_url" => server, "stream_key" => key}, provider: "tiktok", purpose: PURPOSE,
          access_policy: {"consumers" => [CONSUMER], "purposes" => [PURPOSE]}, requested_by: user.email_address)
      end
      def self.output!(user)
        payload = LightekVault::Service.checkout!(slug: slug(user), consumer: CONSUMER, purpose: PURPOSE, requested_by: "user:#{user.id}")
        server, key = validate!(payload["server_url"], payload["stream_key"])
        server + key
      rescue ActiveRecord::RecordNotFound, LightekVault::Service::AccessDenied
        raise Unavailable, "Configure an authorized TikTok streaming destination first."
      end
    end
  end
end
