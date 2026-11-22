# frozen_string_literal: true

require "uri"

module LightekGrowth
  module SearchDiscovery
    SITEMAP_LIMIT = 50_000
    HOST_PATTERN = /\A(?=.{1,253}\z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/i

    module_function

    def origin(site)
      host = site.host.to_s.downcase
      "https://#{host}" if HOST_PATTERN.match?(host) && !host.end_with?(".invalid")
    end

    def canonical_page(site, slug)
      base = origin(site)
      "#{base}/site/#{encode_segment(slug)}" if base && slug.present?
    end

    def sitemap_url(site)
      base = origin(site)
      "#{base}/sitemap.xml" if base
    end

    def encode_segment(value)
      URI.encode_www_form_component(value.to_s).gsub("+", "%20")
    end
  end
end
