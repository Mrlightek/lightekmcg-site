# frozen_string_literal: true

class WebsiteSearchDiscoveryController < ApplicationController
  allow_unauthenticated_access only: %i[robots sitemap]
  skip_authorization_check
  before_action :load_site

  rescue_from(ActiveRecord::RecordNotFound) { head :not_found }

  def robots
    content = ["User-agent: *", "Disallow:", "Sitemap: #{LightekGrowth::SearchDiscovery.sitemap_url(@site)}"]
    render plain: content.join("\n") + "\n"
  end

  def sitemap
    xml = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |builder|
      builder.urlset(xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9") do
        each_public_url do |url|
          builder.url { builder.loc(url) }
        end
      end
    end
    render xml: xml.to_xml, content_type: "application/xml"
  end

  private

  def load_site
    @site = LightekPwa::SiteContext.resolve(request.host)
    @origin = LightekGrowth::SearchDiscovery.origin(@site)
    head :not_found unless @origin
  end

  def each_public_url
    discovery = LightekGrowth::SearchDiscovery
    remaining = discovery::SITEMAP_LIMIT
    @site.pages.published.where.not(slug: [nil, ""]).select(:id, :slug).limit(remaining).find_each do |page|
      yield discovery.canonical_page(@site, page.slug)
      remaining -= 1
    end
    return if remaining.zero?

    LightekBlog::Entry.publicly_visible.where(site: @site).select(:id, :slug).limit(remaining).find_each do |entry|
      yield "#{@origin}/blog/#{discovery.encode_segment(entry.slug)}"
    end
  end
end
