require "net/http"
require "json"
require "digest"
require "base64"
module LightekMail
  class HttpsDelivery
    def initialize(settings = {}) = @settings = settings
    def deliver!(mail)
      raise ArgumentError, "One From address is required." unless mail.from.to_a.size == 1
      recipients = (mail.to.to_a + mail.cc.to_a + mail.bcc.to_a).map(&:downcase).uniq
      envelope = Array(mail.smtp_envelope_to).map(&:downcase).uniq
      raise ArgumentError, "Custom SMTP envelopes are unsupported." unless envelope.sort == recipients.sort
      uri = URI.parse(@settings.fetch(:url) { ENV.fetch("LIGHTEK_MAIL_RELAY_URL", "https://lightekmcg.com/api/lightek-mail/messages") })
      raise ArgumentError, "Use an HTTPS relay endpoint." unless uri.scheme == "https" && uri.userinfo.nil? && uri.fragment.nil?
      token = @settings[:token].presence || LightekVault::Service.checkout!(slug: ENV.fetch("LIGHTEK_MAIL_RELAY_VAULT_SLUG", "lightek-mail-relay"), consumer: self.class.name, purpose: "mail_submission", requested_by: "action-mailer").fetch("token")
      mail.message_id ||= "#{SecureRandom.uuid}@lightek-client"
      text_part = mail.text_part || (!mail.multipart? && mail.mime_type != "text/html" ? mail : nil)
      html_part = mail.html_part || (!mail.multipart? && mail.mime_type == "text/html" ? mail : nil)
      files = mail.attachments.map do |attachment|
        {filename: attachment.filename, content_type: attachment.mime_type, data: Base64.strict_encode64(attachment.body.decoded)}
      end
      body = {from: mail.from.first, to: mail.to.to_a, cc: mail.cc.to_a, bcc: mail.bcc.to_a, subject: mail.subject,
        text: text_part&.decoded.to_s, html: html_part&.decoded.to_s, attachments: files}
      raise ArgumentError, "Message exceeds relay size limit." if JSON.generate(body).bytesize > 14 * 1024 * 1024
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{token}"
      request["Idempotency-Key"] = Digest::SHA256.hexdigest(mail.message_id)
      request.content_type = "application/json"
      request.body = JSON.generate(body)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 20, verify_mode: OpenSSL::SSL::VERIFY_PEER) { |http| http.request(request) }
      raise Submission::Unavailable, "The central mail service did not accept this request (HTTP #{response.code})." unless response.code == "202"
      JSON.parse(response.body)
    end
  end
end
