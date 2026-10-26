require "mail"
require "base64"
require "stringio"
require "digest"
module LightekMail
  class Submission
    class Unavailable < StandardError; end
    MAX_BYTES = 10 * 1024 * 1024
    def self.addresses(value)
      list = Array(value.is_a?(String) ? value.split(",") : value).map(&:to_s)
      raise ArgumentError, "Use 1–20 plain recipient addresses." unless list.length.between?(1, 20) && list.all? { |a| a.bytesize <= 254 && a.match?(/\A[^\s<>@,;]+@(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,63}\z/) }
      list.map(&:downcase).uniq
    end
    def self.create!(account:, attributes:, draft: false, idempotency_key: nil, uploads: [])
      attrs = attributes.to_h.stringify_keys
      to = attrs["to"].present? ? addresses(attrs["to"]) : []
      cc = attrs["cc"].present? ? addresses(attrs["cc"]) : []
      bcc = attrs["bcc"].present? ? addresses(attrs["bcc"]) : []
      recipients = (to + cc + bcc).uniq
      raise ArgumentError, "Use 1–20 unique recipients." unless recipients.length.between?(1, 20)
      subject = attrs["subject"].to_s
      raise ArgumentError, "The sender must match this mailbox." if attrs["from"].present? && attrs["from"].to_s.downcase != account.address
      text, html = attrs["text"].to_s, attrs["html"].to_s
      if attrs["template_id"].present?
        template = account.templates.find(attrs["template_id"])
        rendered = TemplateRenderer.render(template.document, attrs.fetch("variables", {}).to_h.stringify_keys.slice(*TemplateRenderer::VARIABLES))
        text, html = rendered.values_at(:text, :html)
        subject = TemplateRenderer.interpolate(template.subject, attrs.fetch("variables", {}).to_h.stringify_keys)
      else
        html = TemplateRenderer.clean_html(html)
      end
      raise ArgumentError, "Use a subject of 1–200 characters, without newlines." unless subject.length.between?(1, 200) && !subject.match?(/[\r\n]/)
      raise ArgumentError, "Write a message or select a template." if text.blank? && html.blank?
      uploads = Array(uploads).reject(&:blank?)
      encoded = Array(attrs["attachments"]).reject(&:blank?)
      raise ArgumentError, "Attachments must be an array." if attrs["attachments"].present? && !attrs["attachments"].is_a?(Array)
      encoded.each do |file|
        raise ArgumentError, "Invalid attachment." unless file.is_a?(Hash) && file.keys.map(&:to_s).sort == %w[content_type data filename]
        filename = File.basename(file.fetch("filename", file[:filename]).to_s)
        raise ArgumentError, "Invalid attachment filename." unless filename.present? && filename.bytesize <= 180 && !filename.match?(/[\\r\\n]/)
        data = file.fetch("data", file[:data]).to_s
        raise ArgumentError, "Invalid attachment encoding." if data.bytesize > 14 * 1024 * 1024
        bytes = Base64.strict_decode64(data)
        uploads << {io: StringIO.new(bytes), filename: filename, content_type: file.fetch("content_type", file[:content_type]).to_s.presence || "application/octet-stream", byte_size: bytes.bytesize}
      end
      raise ArgumentError, "Use at most 10 attachments." if uploads.length > 10
      size = text.bytesize + html.bytesize + uploads.sum { |upload| upload.is_a?(Hash) ? upload.fetch(:byte_size) : upload.size }
      raise ArgumentError, "Message and attachments must total at most 10 MB." if size > MAX_BYTES
      if idempotency_key
        raise ArgumentError, "Use an Idempotency-Key of 8–100 letters, digits, underscores or hyphens." unless idempotency_key.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
      end
      created = false
      result = SendingPolicy.synchronize do |policy|
        account.with_lock do
          existing = account.messages.find_by(idempotency_key: idempotency_key) if idempotency_key
          if existing
            matching = existing.from_address == account.address && existing.to_addresses.sort == recipients.sort &&
              existing.cc_addresses == cc && existing.bcc_addresses == bcc && existing.subject == subject &&
              existing.text_body.to_s == text && existing.html_body.to_s == html && existing.bytesize == size
            raise ArgumentError, "Idempotency-Key already used for different content." unless matching
            next existing
          end
          raise Unavailable, "Mailbox storage is full." if account.messages.sum(:bytesize) + size > account.storage_limit
          message = account.messages.create!(direction: "outbound", state: "draft", from_address: account.address, to_addresses: to, cc_addresses: cc, bcc_addresses: bcc, subject: subject,
            text_body: text, html_body: html, bytesize: size, message_id: "#{SecureRandom.uuid}@#{account.domain.name}", in_reply_to: attrs["in_reply_to"].to_s.slice(0, 250).delete("\r\n"), idempotency_key: idempotency_key)
          uploads.each { |upload| message.attachments.attach(upload.is_a?(Hash) ? upload.except(:byte_size) : upload) }
          SendingLimits.reserve!(policy, account, message) unless draft
          created = true
          message
        end
      end
      DeliverJob.perform_later(result.id) if created && result.state == "queued"
      result
    end
    def self.send_draft!(account, message)
      SendingPolicy.synchronize do |policy|
        account.with_lock do
          message.reload
          raise Unavailable, "Only an unsent draft can be sent." unless message.account_id == account.id && message.state == "draft"
          SendingLimits.reserve!(policy, account, message)
        end
      end
      DeliverJob.perform_later(message.id)
    end
  end
end
