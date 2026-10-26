# frozen_string_literal: true
require "uri"
module Studio
  module Live
    class Destination
      class Unavailable < StandardError; end
      CONSUMER = "Studio::Live::Destination"
      PURPOSE = "live_broadcast"
      PROVIDERS = {
        "tiktok" => {label: "TikTok", hosts: %w[tiktok.com tiktokv.com tiktokcdn.com tiktokcdn-us.com ttlivecdn.com]},
        "restream" => {label: "Restream", hosts: %w[restream.io]}
      }.freeze

      def self.provider!(provider)
        PROVIDERS.fetch(provider.to_s) { raise Unavailable, "Choose TikTok or Restream as the streaming provider." }
      end
      def self.slug(user, provider: "tiktok")
        provider!(provider)
        "studio-live-#{user.id}-#{provider}"
      end
      def self.configured?(user, provider: "tiktok")
        LightekVault::Secret.where(slug: slug(user, provider: provider), status: "active").where("expires_at IS NULL OR expires_at > ?", Time.current).exists?
      end
      def self.validate!(server_url, stream_key, provider: "tiktok")
        config = provider!(provider)
        uri = URI.parse(server_url.to_s.strip)
        host = uri.host.to_s.downcase
        valid_host = config[:hosts].any? { |suffix| host.end_with?(".#{suffix}") }
        raise Unavailable, "Use the RTMP or RTMPS server URL supplied by #{config[:label]}." unless %w[rtmp rtmps].include?(uri.scheme) && valid_host && uri.userinfo.nil? && uri.fragment.nil? && uri.query.nil? && [443, 1935].include?(uri.port || (uri.scheme == "rtmps" ? 443 : 1935))
        key = stream_key.to_s.strip
        raise Unavailable, "Enter the stream key supplied by #{config[:label]}." if key.empty? || key.bytesize > 2048 || key.match?(/[\s\x00-\x1f]/)
        [uri.to_s.sub(%r{/+\z}, "") + "/", key]
      rescue URI::InvalidURIError
        raise Unavailable, "Use the server URL supplied by the selected streaming provider."
      end
      def self.save!(user:, server_url:, stream_key:, provider: "tiktok")
        ::Gatekeeper::StudioLivePolicy.authorize!(user: user, configure: true)
        server, key = validate!(server_url, stream_key, provider: provider)
        LightekVault::Service.store!(name: "#{provider!(provider)[:label]} LIVE · #{user.id}", slug: slug(user, provider: provider), payload: {"server_url" => server, "stream_key" => key}, provider: provider.to_s, purpose: PURPOSE,
          access_policy: {"consumers" => [CONSUMER], "purposes" => [PURPOSE]}, requested_by: user.email_address)
      end
      def self.output!(user, provider: "tiktok")
        payload = LightekVault::Service.checkout!(slug: slug(user, provider: provider), consumer: CONSUMER, purpose: PURPOSE, requested_by: "user:#{user.id}")
        server, key = validate!(payload["server_url"], payload["stream_key"], provider: provider)
        server + key
      rescue ActiveRecord::RecordNotFound, LightekVault::Service::AccessDenied
        raise Unavailable, "Configure an authorized streaming destination for the selected provider first."
      end
    end
  end
end
