require "net/http"
require "json"

module LightekMail
  class SpamScanner
    class Unavailable < StandardError; end
    class Rejected < StandardError; end

    def self.check!(mail)
      result = scan!(mail)
      action, score = result.values_at("action", "score")
      raise Unavailable, "Spam scanner temporarily deferred this message." if action.in?(%w[greylist soft\ reject])
      raise Rejected, "Outbound message blocked by spam scanning; administrator review required." if action != "no action" || score >= 6
      true
    end

    def self.scan!(mail, raw: nil)
      uri = URI.parse(ENV.fetch("LIGHTEK_MAIL_RSPAMD_URL", "http://127.0.0.1:11333/checkv2"))
      unless uri.scheme == "http" && %w[127.0.0.1 ::1].include?(uri.hostname) && uri.path == "/checkv2" && !uri.userinfo && !uri.query && !uri.fragment
        raise Unavailable, "Use a loopback Rspamd checkv2 endpoint."
      end
      request = Net::HTTP::Post.new(uri)
      request.content_type = "message/rfc822"
      request["From"] = Array(mail.from).first.to_s
      request["User"] = Array(mail.from).first.to_s
      request["Rcpt"] = Array(mail.to).join(",")
      request.body = raw || mail.encoded
      # Explicitly bypass HTTP proxies for this loopback-only service.
      response = Net::HTTP.start(uri.hostname, uri.port, nil, open_timeout: 3, read_timeout: 20) { |http| http.request(request) }
      raise Unavailable, "Spam scanner unavailable; no SMTP submission attempted." unless response.code == "200" && response.body.bytesize <= 1_048_576
      result = JSON.parse(response.body)
      action = result.fetch("action")
      score = Float(result.fetch("score"))
      raise Unavailable, "Invalid spam scanner response." unless score.finite? && %w[no\ action greylist add\ header rewrite\ subject soft\ reject reject discard quarantine].include?(action)
      {"action" => action, "score" => score, "dkim_domains" => dkim_domains(result, raw)}
    rescue KeyError, JSON::ParserError, ArgumentError, TypeError, SocketError, IOError, SystemCallError, Timeout::Error
      raise Unavailable, "Spam scanner unavailable; no SMTP submission attempted."
    end
    def self.dkim_domains(result, raw)
      # Trust only the scanner result for the original SMTP bytes. Require
      # full-body signatures and one From header before treating it as aligned.
      return [] unless raw

      headers = raw.b.split(/\r?\n\r?\n/, 2).first.to_s.gsub(/\r?\n[ \t]+/, " ")
      return [] unless headers.scan(/^From:/i).one?

      signatures = headers.scan(/^DKIM-Signature:[^\r\n]*/i)
      return [] if signatures.empty? || signatures.any? { |signature| signature.match?(/(?:;|:)\s*l\s*=/i) }

      symbol = result["symbols"]
      allowed = symbol["R_DKIM_ALLOW"] if symbol.is_a?(Hash)
      return [] unless allowed.is_a?(Hash)

      Array(allowed["options"]).filter_map do |option|
        option.to_s[/\A([a-z0-9-]+(?:\.[a-z0-9-]+)+)(?::s=[a-z0-9_.-]+)?\z/i, 1]&.downcase
      end.uniq
    end
    private_class_method :dkim_domains
  end
end
