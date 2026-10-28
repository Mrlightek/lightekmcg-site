# frozen_string_literal: true
require "net/http"
require "json"
require "uri"

module LightekMarketing
  class MetaOauth
    class Error < StandardError; end
    GRAPH = "https://graph.facebook.com/v22.0".freeze
    LOGIN = "https://www.facebook.com/v22.0/dialog/oauth".freeze

    def self.app_credentials
      data = LightekVault::Service.checkout!(slug: "lightek-meta-oauth-app",
        consumer: "lightek_marketing", purpose: "social_oauth", requested_by: "lightek_marketing/meta_oauth")
      id, secret = data.values_at("app_id", "app_secret")
      raise Error, "Meta OAuth application credentials missing" if id.blank? || secret.blank?
      [id, secret]
    end

    def self.authorization_url(redirect_uri:, state:)
      app_id, = app_credentials
      uri = URI(LOGIN)
      uri.query = URI.encode_www_form(client_id: app_id, redirect_uri: redirect_uri, state: state,
        response_type: "code", scope: "pages_show_list,pages_read_engagement,pages_manage_posts,instagram_basic,instagram_content_publish")
      uri.to_s
    end

    def self.exchange!(code:, redirect_uri:)
      app_id, app_secret = app_credentials
      short = get!("/oauth/access_token", client_id: app_id, client_secret: app_secret,
        redirect_uri: redirect_uri, code: code)
      long = get!("/oauth/access_token", grant_type: "fb_exchange_token",
        client_id: app_id, client_secret: app_secret, fb_exchange_token: short.fetch("access_token"))
      long.fetch("access_token")
    end

    def self.pages!(user_token:)
      get!("/me/accounts", access_token: user_token, fields: "id,name,access_token,instagram_business_account{id}")
        .fetch("data", [])
    end

    def self.store_pages!(site:, actor:, pages:)
      pages.each do |page|
        page_id, page_token = page.values_at("id", "access_token")
        raise Error, "Page missing credentials" if page_id.blank? || page_token.blank?
        label = "Facebook #{page_id}"
        SocialVault.store!(site: site, provider: "facebook", account: label,
          credentials: {"page_id" => page_id, "access_token" => page_token}, actor: actor)
        upsert!(site: site, provider: "facebook", label: label)
        instagram_id = page.dig("instagram_business_account", "id")
        next if instagram_id.blank?
        ig_label = "Instagram #{instagram_id}"
        SocialVault.store!(site: site, provider: "instagram", account: ig_label,
          credentials: {"instagram_user_id" => instagram_id, "access_token" => page_token}, actor: actor)
        upsert!(site: site, provider: "instagram", label: ig_label)
      end
    end

    def self.upsert!(site:, provider:, label:)
      SocialConnection.find_or_initialize_by(site: site, provider: provider, account_label: label).tap do |connection|
        connection.assign_attributes(credential_key: SocialVault.slug(site_id: site.id, provider: provider, account: label),
          publish_endpoint: GRAPH, enabled: true, disabled_at: nil)
        connection.save!
      end
    end

    def self.get!(path, query)
      uri = URI("#{GRAPH}#{path}")
      uri.query = URI.encode_www_form(query)
      request = Net::HTTP::Get.new(uri.request_uri)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 15) { |http| http.request(request) }
      data = JSON.parse(response.body)
      raise Error, "Meta authorization failed (#{response.code}): #{data.dig("error", "message")}" unless response.is_a?(Net::HTTPSuccess)
      data
    rescue JSON::ParserError
      raise Error, "Meta returned invalid JSON"
    end
  end
end
