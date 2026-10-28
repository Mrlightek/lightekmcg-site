# frozen_string_literal: true
require "net/http"
require "json"
require "uri"

module LightekMarketing
  class TiktokOauth
    class Error < StandardError; end
    AUTHORIZE = "https://www.tiktok.com/v2/auth/authorize/".freeze
    TOKEN = URI("https://open.tiktokapis.com/v2/oauth/token/").freeze

    def self.application_credentials
      data = LightekVault::Service.checkout!(slug: "lightek-tiktok-oauth-app",
        consumer: "lightek_marketing", purpose: "social_oauth",
        requested_by: "lightek_marketing/tiktok_oauth")
      key, secret = data.values_at("client_key", "client_secret")
      raise Error, "TikTok OAuth app credentials are incomplete" if key.blank? || secret.blank?
      [key, secret]
    end

    def self.authorize_url(state:, redirect_uri:)
      key, = application_credentials
      uri = URI(AUTHORIZE)
      uri.query = URI.encode_www_form(client_key: key, response_type: "code",
        scope: "user.info.basic,video.upload", redirect_uri: redirect_uri, state: state)
      uri.to_s
    end

    def self.exchange!(code:, redirect_uri:)
      key, secret = application_credentials
      token_request!("authorization_code", client_key: key, client_secret: secret,
        code: code, redirect_uri: redirect_uri)
    end

    def self.refresh!(refresh_token:)
      key, secret = application_credentials
      token_request!("refresh_token", client_key: key, client_secret: secret,
        refresh_token: refresh_token)
    end

    def self.token_request!(grant_type, parameters)
      request = Net::HTTP::Post.new(TOKEN.request_uri, "Content-Type" => "application/x-www-form-urlencoded")
      request.body = URI.encode_www_form(parameters.merge(grant_type: grant_type))
      response = Net::HTTP.start(TOKEN.host, TOKEN.port, use_ssl: true, open_timeout: 5, read_timeout: 15) { |http| http.request(request) }
      data = JSON.parse(response.body)
      raise Error, "TikTok OAuth failed: #{data.fetch("error", response.code)}" unless response.is_a?(Net::HTTPSuccess) && data["access_token"].present? && data["refresh_token"].present?
      data
    rescue JSON::ParserError
      raise Error, "TikTok returned an invalid token response"
    end

    def self.store_tokens!(site:, user:, tokens:)
      open_id = tokens.fetch("open_id")
      label = "TikTok #{open_id.to_s.first(30)}"
      credentials = {
        "access_token" => tokens.fetch("access_token"),
        "refresh_token" => tokens.fetch("refresh_token"),
        "open_id" => open_id.to_s,
        "scope" => tokens["scope"].to_s,
        "expires_at" => (Time.current + tokens.fetch("expires_in").to_i.seconds).iso8601
      }
      LightekMarketing::SocialVault.store!(site: site, provider: "tiktok", account: label,
        credentials: credentials, actor: user)
      LightekMarketing::SocialConnection.find_or_initialize_by(site: site, provider: "tiktok", account_label: label).tap do |connection|
        connection.assign_attributes(credential_key: LightekMarketing::SocialVault.slug(site_id: site.id, provider: "tiktok", account: label),
          publish_endpoint: "https://open.tiktokapis.com", enabled: true, disabled_at: nil)
        connection.save!
      end
    end
  end
end
