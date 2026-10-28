# frozen_string_literal: true
require "net/http"
require "json"
module LightekMarketing
  # Integration point for an operator-approved social publishing gateway.
  # No arbitrary user-controlled URL requests or fake provider OAuth.
  class SocialDispatch
    class Unavailable < StandardError; end
    def self.call!(post:)
      post.with_lock do
        connection = post.connection
        campaign = post.campaign
        raise Unavailable, "Campaign is not ready" unless campaign.status == "ready" && campaign.channel == "social"
        raise Unavailable, "Connection unavailable" unless connection.enabled? && connection.site_id == campaign.site_id
        configured = ENV.fetch("LIGHTEK_SOCIAL_PUBLISH_GATEWAY_URL", "")
        raise Unavailable, "Trusted social gateway has not been configured" if configured.blank?
        uri = URI.parse(configured)
        raise Unavailable, "HTTPS gateway required" unless uri.scheme == "https" && uri.host.present? && uri.userinfo.nil?
        key = ENV.fetch("LIGHTEK_SOCIAL_PUBLISH_GATEWAY_TOKEN", "")
        raise Unavailable, "Gateway token missing" if key.blank?
        request = Net::HTTP::Post.new(uri.request_uri, {"Content-Type" => "application/json", "Authorization" => "Bearer #{key}", "Idempotency-Key" => "lightek-social-#{post.id}"})
        request.body = {provider: connection.provider, account: connection.account_label,
          campaign_id: campaign.id, text: [campaign.headline, campaign.message, campaign.cta_url].compact.join("\n\n")}.to_json
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 20) { |http| http.request(request) }
        raise Unavailable, "Gateway rejected publish request (#{response.code})" unless response.is_a?(Net::HTTPSuccess)
        result = JSON.parse(response.body)
        raise Unavailable, "Gateway did not return publication confirmation" if result["remote_id"].blank?
        post.update!(status: "published", remote_id: result["remote_id"].to_s.slice(0, 255), published_at: Time.current)
      end
    end
  end
end
