require 'openssl'
require 'base64'
require 'net/http'
require 'uri'
module LightekSessions
  class Media
    class Unavailable < StandardError; end
    CONSUMER = 'LightekSessions::Media'
    PURPOSE = 'session_media'
    def initialize(site)
      @site = site
    end
    def self.slug(site) = "session-media-#{site.id}"
    def self.configured?(site)
      LightekVault::Secret.where(slug: slug(site), status: 'active').where('expires_at IS NULL OR expires_at > ?', Time.current).exists?
    end
    def credentials
      @credentials ||= LightekVault::Service.checkout!(slug: self.class.slug(@site), consumer: CONSUMER,
        purpose: PURPOSE, requested_by: 'Lightek session service')
    rescue ActiveRecord::RecordNotFound, LightekVault::Service::AccessDenied
      raise Unavailable, 'Your host needs to activate Lightek session media in Dashboard.'
    end
    def url
      uri = URI.parse(credentials.fetch('url'))
      raise Unavailable, 'Use a secure media endpoint.' unless uri.scheme == 'wss' && uri.host.present? && !uri.userinfo && !uri.query && !uri.fragment
      uri.to_s.sub(%r{/+$}, '')
    end
    def jwt(identity:, grant:, ttl: 45, name: nil)
      encode = ->(value) { Base64.urlsafe_encode64(JSON.generate(value), padding: false) }
      data = {iss: credentials.fetch('api_key'), sub: identity, nbf: Time.current.to_i - 5,
        exp: Time.current.to_i + ttl, jti: SecureRandom.uuid, video: grant}
      data[:name] = name if name
      signing = [encode.call({alg: 'HS256', typ: 'JWT'}), encode.call(data)].join('.')
      signing + '.' + Base64.urlsafe_encode64(OpenSSL::HMAC.digest('SHA256', credentials.fetch('api_secret'), signing), padding: false)
    end
    def call(method, body, room: nil)
      raise Unavailable, 'Unsupported media operation.' unless %w[CreateRoom DeleteRoom ListParticipants RemoveParticipant MutePublishedTrack].include?(method)
      uri = URI.parse(url.sub(/\Awss:/, 'https:') + '/twirp/livekit.RoomService/' + method)
      request = Net::HTTP::Post.new(uri)
      grant = %w[CreateRoom DeleteRoom].include?(method) ? {roomCreate: true} : {roomAdmin: true, room: room}
      request['Authorization'] = 'Bearer ' + jwt(identity: 'lightek-service', grant: grant)
      request['Content-Type'] = 'application/json'
      request.body = JSON.generate(body)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.request(request) }
      return {} if response.code == '404' && method == 'DeleteRoom'
      raise Unavailable, "Session media returned HTTP #{response.code}." unless response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body)
    rescue IOError, SystemCallError, Timeout::Error, JSON::ParserError, OpenSSL::SSL::SSLError
      raise Unavailable, 'Session media is temporarily unavailable. Please try again.'
    end
    def join!(room, user, studio: false)
      Access.authorize!(room, user, joining: true)
      Access.host!(room, user) if studio
      host = room.host?(user)
      call('CreateRoom', {name: room.media_name, empty_timeout: 300, departure_timeout: 60,
        max_participants: [room.resource.capacity + 4, 1004].min}, room: room.media_name)
      Access.authorize!(room.reload, user, joining: true)
      publish = !studio && (host || !room.live?)
      sources = room.resource.kind == 'voice' ? ['microphone'] : %w[camera microphone screen_share screen_share_audio]
      token = jwt(identity: "user-#{user.id}#{studio ? '-studio' : ''}", name: user.first_name.to_s.first(80),
        ttl: [45, (room.ends_at - Time.current).floor].min.clamp(1, 45), grant: {room: room.media_name, roomJoin: true, canSubscribe: true, canPublish: publish,
          canPublishData: !studio, canUpdateOwnMetadata: false, canPublishSources: publish ? sources : []})
      {url: url, token: token, publish: publish, voice_only: room.resource.kind == 'voice',
        host: host, room_generation: room.media_name, ends_at: room.ends_at.iso8601, studio: studio}
    end
  end
end
