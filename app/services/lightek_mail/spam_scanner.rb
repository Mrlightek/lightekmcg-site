require "net/http"
require "json"

module LightekMail
  class SpamScanner
    class Unavailable < StandardError; end
    class Rejected < StandardError; end

    def self.check!(mail)
      uri = URI.parse(ENV.fetch("LIGHTEK_MAIL_RSPAMD_URL", "http://127.0.0.1:11333/checkv2"))
      unless uri.scheme == "http" && %w[127.0.0.1 ::1].include?(uri.hostname) && uri.path == "/checkv2" && !uri.userinfo && !uri.query && !uri.fragment
        raise Unavailable, "Use a loopback Rspamd checkv2 endpoint."
      end
      request = Net::HTTP::Post.new(uri)
      request.content_type = "message/rfc822"
      request["From"] = mail.from.first
      request["User"] = mail.from.first
      request["Rcpt"] = mail.to.join(",")
      request.body = mail.encoded
      # Explicitly bypass HTTP proxies for this loopback-only service.
      response = Net::HTTP.start(uri.hostname, uri.port, nil, open_timeout: 3, read_timeout: 20) { |http| http.request(request) }
      raise Unavailable, "Spam scanner unavailable; no SMTP submission attempted." unless response.code == "200" && response.body.bytesize <= 1_048_576
      result = JSON.parse(response.body)
      action = result.fetch("action")
      score = Float(result.fetch("score"))
      raise Unavailable, "Invalid spam scanner response." unless score.finite? && %w[no\ action greylist add\ header rewrite\ subject soft\ reject reject discard quarantine].include?(action)
      raise Unavailable, "Spam scanner temporarily deferred this message." if action.in?(%w[greylist soft\ reject])
      raise Rejected, "Outbound message blocked by spam scanning; administrator review required." if action != "no action" || score >= 6
      true
    rescue KeyError, JSON::ParserError, ArgumentError, TypeError, SocketError, IOError, SystemCallError, Timeout::Error
      raise Unavailable, "Spam scanner unavailable; no SMTP submission attempted."
    end
  end
end
