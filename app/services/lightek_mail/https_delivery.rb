require "net/http"
require "json"
require "digest"
module LightekMail
  # Install this adapter on a client Rails instance to submit through the central relay.
  class HttpsDelivery
    def initialize(settings = {}) = @settings = settings
    def deliver!(mail)
      if mail.cc.to_a.any? || mail.bcc.to_a.any? || mail.from.to_a.size != 1 || Array(mail.smtp_envelope_to).map(&:downcase).sort != mail.to.to_a.map(&:downcase).sort
        raise ArgumentError, "The HTTPS relay supports one From and To recipients only; Cc, Bcc and custom SMTP envelopes are not supported."
      end
      uri = URI.parse(@settings.fetch(:url) { ENV.fetch("LIGHTEK_MAIL_RELAY_URL", "https://lightekmcg.com/api/lightek-mail/messages") })
      raise ArgumentError, "Use an HTTPS relay endpoint." unless uri.scheme == "https" && uri.userinfo.nil? && uri.fragment.nil?
      token = @settings[:token].presence || LightekVault::Service.checkout!(slug: ENV.fetch("LIGHTEK_MAIL_RELAY_VAULT_SLUG", "lightek-mail-relay"), consumer: self.class.name, purpose: "mail_submission", requested_by: "action-mailer").fetch("token")
      raise ArgumentError, "HTTPS relay attachments are not supported; use Mail Studio for attachments." if mail.attachments.any?
      mail.message_id ||= "#{SecureRandom.uuid}@lightek-client"
      text_part = mail.text_part || (!mail.multipart? && mail.mime_type != "text/html" ? mail : nil)
      html_part = mail.html_part || (!mail.multipart? && mail.mime_type == "text/html" ? mail : nil)
      body = {from: mail.from&.first, to: mail.to, subject: mail.subject, text: text_part&.decoded.to_s, html: html_part&.decoded.to_s}
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{token}"
      request["Idempotency-Key"] = Digest::SHA256.hexdigest(mail.message_id)
      request.content_type = "application/json"
      request.body = JSON.generate(body)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 20, verify_mode: OpenSSL::SSL::VERIFY_PEER) { |http| http.request(request) }
      raise Submission::Unavailable, "The central mail service did not accept this request (HTTP #{response.code})." unless response.code == "202"
      # This is queue acceptance, not SMTP acceptance or final recipient delivery.
      JSON.parse(response.body)
    end
  end
end
