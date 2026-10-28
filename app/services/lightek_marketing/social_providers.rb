# frozen_string_literal: true
require "net/http"
require "json"
require "uri"
module LightekMarketing
  module SocialProviders
    class Error < StandardError; end
    def self.publish!(connection:, campaign:)
      raise Error, "Unsupported provider" unless %w[facebook instagram tiktok].include?(connection.provider)
      creds = SocialVault.checkout!(connection: connection)
      text = [campaign.headline, campaign.message, campaign.cta_url].reject(&:blank?).join("\n\n")
      case connection.provider
      when "facebook"
        graph_post!("https://graph.facebook.com/v22.0/#{CGI.escape(creds.fetch("page_id"))}/feed",
          {message: text, access_token: creds.fetch("access_token")})
      when "instagram"
        raise Error, "Instagram requires a publicly reachable media URL in CTA URL" unless campaign.media_url.to_s.match?(/\Ahttps:\/\/.+\.(jpg|jpeg|png)(\?.*)?\z/i)
        base = "https://graph.facebook.com/v22.0/#{CGI.escape(creds.fetch("instagram_user_id"))}"
        container = graph_post!("#{base}/media", {image_url: campaign.media_url, caption: text, access_token: creds.fetch("access_token")})
        graph_post!("#{base}/media_publish", {creation_id: container, access_token: creds.fetch("access_token")})
      when "tiktok"
        raise Error, "TikTok Direct Post requires approved video/upload workflow; no false publish confirmation"
      else
        raise Error, "Unsupported provider"
      end
    end
    def self.graph_post!(url, values)
      uri = URI.parse(url)
      response = Net::HTTP.post_form(uri, values)
      data = JSON.parse(response.body)
      raise Error, "Provider rejected publication (#{response.code}): #{data.dig("error", "message")}" unless response.is_a?(Net::HTTPSuccess) && data["id"].present?
      data.fetch("id")
    end
  end
end
