require 'net/http'
require 'json'
require 'uri'

module LightekGrowth
  class SearchConsole
    class Unavailable < StandardError; end

    PURPOSE = 'search_console_read'
    ROW_LIMIT = 250
    TIMEOUT = 8

    def initialize(actor:, site:)
      @actor, @site = actor, site
      @access = Workspace.new(actor: actor, site: site)
    end

    def sync!(inspection_url: nil, domain: false)
      property = domain ? "sc-domain:#{@site.host.downcase}" : "#{SearchDiscovery.origin(@site)}/"
      raise ArgumentError, 'Select a public site hostname.' unless SearchDiscovery.origin(@site)

      page = Backlink.url(inspection_url) if inspection_url.present?
      if inspection_url.present? && !(page && page.scheme == 'https' && page.host.casecmp?(@site.host) && page.port == 443)
        raise ArgumentError, 'Enter an HTTPS page on this website to inspect.'
      end

      ending = 3.days.ago.to_date
      starting = ending - 27
      encoded = URI.encode_www_form_component(property)
      response = post(URI("https://www.googleapis.com/webmasters/v3/sites/#{encoded}/searchAnalytics/query"),
        { startDate: starting.iso8601, endDate: ending.iso8601, dimensions: %w[page query], rowLimit: ROW_LIMIT, dataState: 'final' },
        token: token)
      rows = Array(response['rows']).first(ROW_LIMIT).filter_map { |row| search_row(row) }
      inspection = inspect_page(page, property) if page
      @access.revalidate!
      SearchSnapshot.create!(site: @site, created_by: @actor, property: property, starts_on: starting, ends_on: ending,
        rows: rows, inspection: inspection)
    rescue LightekVault::Service::AccessDenied, ActiveRecord::RecordNotFound, KeyError, JSON::ParserError, IOError, SystemCallError,
        Timeout::Error, OpenSSL::SSL::SSLError, SocketError
      raise Unavailable, 'Search Console could not be refreshed. Check the Vault credential, property access and network connection.'
    end

    private

    def search_row(row)
      page, query = row.fetch('keys')
      uri = Backlink.url(page)
      return unless uri && uri.host.casecmp?(@site.host) && query.is_a?(String)

      metrics = row.slice('clicks', 'impressions', 'ctr', 'position')
      return unless metrics.size == 4 && metrics.values.all? { |value| value.is_a?(Numeric) && value.finite? && value >= 0 }

      metrics.merge('page' => page, 'query' => query.first(500))
    end

    def inspect_page(page, property)
      response = post(URI('https://searchconsole.googleapis.com/v1/urlInspection/index:inspect'),
        { inspectionUrl: page.to_s, siteUrl: property }, token: token)
      result = response.fetch('inspectionResult').fetch('indexStatusResult')
      result.slice('verdict', 'coverageState', 'lastCrawlTime', 'googleCanonical').merge('page' => page.to_s)
    end

    def token
      @token ||= begin
        credential = LightekVault::Service.checkout!(slug: "growth-search-console-#{@site.id}", consumer: self.class.name,
          purpose: PURPOSE, requested_by: "user:#{@actor.id}")
        post(URI('https://oauth2.googleapis.com/token'), {
          client_id: credential.fetch('client_id'), client_secret: credential.fetch('client_secret'),
          refresh_token: credential.fetch('refresh_token'), grant_type: 'refresh_token'
        }).fetch('access_token')
      end
    end

    def post(uri, data, token: nil)
      request = Net::HTTP::Post.new(uri)
      if token
        request['Authorization'] = "Bearer #{token}"
        request.content_type = 'application/json'
        request.body = JSON.generate(data)
      else
        request.set_form_data(data)
      end
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = http.read_timeout = http.write_timeout = TIMEOUT
      response = http.request(request)
      raise Unavailable, "Search Console request failed (HTTP #{response.code}). Check access to the selected property." unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end
  end
end
