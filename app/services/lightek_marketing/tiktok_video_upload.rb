# frozen_string_literal: true
require "net/http"
require "json"
require "uri"

module LightekMarketing
  # Uses TikTok's Content Posting API (video.upload) to send a verified-domain
  # video to the user's inbox for review. This does NOT publish a public post.
  class TiktokVideoUpload
    class Invalid < StandardError; end
    ENDPOINT = URI("https://open.tiktokapis.com/v2/post/publish/inbox/video/init/").freeze
    STATUS_ENDPOINT = URI("https://open.tiktokapis.com/v2/post/publish/status/fetch/").freeze

    def self.submit!(connection:, campaign:)
      raise Invalid, "TikTok connection required" unless connection.provider == "tiktok"
      raise Invalid, "Only a ready social campaign can be submitted" unless campaign.channel == "social" && campaign.status == "ready"
      url = campaign.media_url.to_s
      uri = URI.parse(url)
      raise Invalid, "Provide a public HTTPS video URL" unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil? && uri.fragment.nil?
      raise Invalid, "Video must be hosted under an operator-verified TikTok domain" unless verified_host?(uri.host)
      TiktokTokenRefreshJob.perform_now(connection.id) if SocialVault.checkout!(connection: connection)["refresh_token"].present?
      credentials = SocialVault.checkout!(connection: connection)
      token = credentials.fetch("access_token")
      response = request!(ENDPOINT, token, {source_info: {source: "PULL_FROM_URL", video_url: url}})
      publish_id = response.dig("data", "publish_id")
      raise Invalid, "TikTok did not return a publish ID" if publish_id.blank?
      publish_id.to_s
    rescue URI::InvalidURIError
      raise Invalid, "Invalid video URL"
    end

    def self.status!(connection:, publish_id:)
      token = SocialVault.checkout!(connection: connection).fetch("access_token")
      result = request!(STATUS_ENDPOINT, token, {publish_id: publish_id})
      result.fetch("data")
    end

    def self.verified_host?(host)
      configured = ENV.fetch("LIGHTEK_TIKTOK_VERIFIED_VIDEO_HOSTS", "")
      configured.split(",").map(&:strip).reject(&:blank?).any? { |domain| host.casecmp?(domain) }
    end

    def self.request!(uri, token, body)
      req = Net::HTTP::Post.new(uri.request_uri, {"Authorization" => "Bearer #{token}", "Content-Type" => "application/json"})
      req.body = JSON.generate(body)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 20) { |http| http.request(req) }
      parsed = JSON.parse(response.body)
      raise Invalid, "TikTok request failed (#{response.code}): #{parsed.dig("error", "code")}" unless response.is_a?(Net::HTTPSuccess) && parsed.dig("error", "code") == "ok"
      parsed
    end
  end
end
