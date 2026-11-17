require 'net/http'
require 'json'
module LightekPwa
  class YoutubeApi
    class Unavailable < StandardError; end
    CONSUMER = name.freeze
    def initialize(credential_slug: LaunchSettings.value('youtube_credential_slug'), channel_id: LaunchSettings.value('youtube_channel_id'))
      slug = credential_slug.presence or raise Unavailable, 'YouTube channel is not configured'
      @channel_id = channel_id.to_s
      @credentials = LightekVault::Service.checkout!(slug: slug, consumer: CONSUMER, purpose: 'youtube_publishing', requested_by: 'pwa-youtube-worker')
    end
    def request(method, url, body: nil, headers: {})
      uri = URI.parse(url)
      raise Unavailable, 'Invalid YouTube API destination' unless uri.is_a?(URI::HTTPS) && uri.host == 'www.googleapis.com' && uri.port == 443 && !uri.userinfo && !uri.fragment &&
        (uri.path == '/upload/youtube/v3/videos' || uri.path.start_with?('/youtube/v3/'))
      klass = {get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put, delete: Net::HTTP::Delete}.fetch(method)
      req = klass.new(uri)
      headers.each { |key, value| req[key] = value }
      req['Authorization'] = "Bearer #{access_token}"
      req.body = body if body
      Net::HTTP.start(uri.host, 443, use_ssl: true, open_timeout: 5, read_timeout: 60, write_timeout: 60) { |http| http.request(req) }
    end
    def access_token
      return @access_token if @access_token
      uri = URI('https://oauth2.googleapis.com/token')
      request = Net::HTTP::Post.new(uri)
      request.set_form_data(client_id: @credentials.fetch('client_id'), client_secret: @credentials.fetch('client_secret'), refresh_token: @credentials.fetch('refresh_token'), grant_type: 'refresh_token')
      response = Net::HTTP.start(uri.host,443,use_ssl:true,open_timeout:5,read_timeout:20) { |http| http.request(request) }
      raise Unavailable, 'YouTube channel authorization needs attention' unless response.is_a?(Net::HTTPSuccess)
      @access_token = JSON.parse(response.body).fetch('access_token')
    rescue JSON::ParserError, KeyError
      raise Unavailable, 'Channel authorization response could not be read'
    end
    def channel!
      response = request(:get, 'https://www.googleapis.com/youtube/v3/channels?part=id&mine=true')
      data = json!(response)
      expected = @channel_id
      raise Unavailable, 'The authorized YouTube channel does not match Lightek’s channel' unless expected.match?(/\AUC[A-Za-z0-9_-]{22}\z/) && data.fetch('items').one? && data['items'].first['id'] == expected
      expected
    end
    def json!(response)
      raise Unavailable, "YouTube request could not be confirmed (HTTP #{response.code})" unless response.is_a?(Net::HTTPSuccess)
      raise Unavailable, 'YouTube response is too large' if response.body.to_s.bytesize > 1.megabyte
      JSON.parse(response.body)
    rescue JSON::ParserError
      raise Unavailable, 'YouTube response could not be read'
    end
    def close
      @access_token&.clear
      @credentials&.each_value { |v| v.clear if v.is_a?(String) && !v.frozen? }
    end
  end
end
