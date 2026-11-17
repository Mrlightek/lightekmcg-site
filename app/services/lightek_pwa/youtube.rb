require 'uri'
module LightekPwa
  class Youtube
    ID = /\A[A-Za-z0-9_-]{11}\z/
    def self.video_id(value)
      uri = URI.parse(value.to_s.strip)
      raise ArgumentError, 'Enter a valid HTTPS YouTube video URL' unless uri.is_a?(URI::HTTPS) && !uri.userinfo && (!uri.port || uri.port == 443)
      id = case uri.host&.downcase
      when 'youtu.be' then uri.path.delete_prefix('/')
      when 'youtube.com', 'www.youtube.com', 'm.youtube.com'
        if uri.path == '/watch'
          URI.decode_www_form(uri.query.to_s).to_h['v']
        else
          match = uri.path.match(%r{\A/(?:shorts|embed|live)/([A-Za-z0-9_-]{11})/?\z})
          match && match[1]
        end
      end
      raise ArgumentError, 'Enter a valid HTTPS YouTube video URL' unless id.to_s.match?(ID)
      id
    rescue URI::InvalidURIError
      raise ArgumentError, 'Enter a valid HTTPS YouTube video URL'
    end
  end
end
