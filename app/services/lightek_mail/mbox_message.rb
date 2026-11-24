require "digest"
require "time"

module LightekMail
  class MboxMessage
    class InvalidMessage < StandardError; end

    MAX_ATTACHMENTS = 40
    Attachment = Struct.new(:filename, :content_type, :bytes, keyword_init: true)

    attr_reader :raw, :identity, :idempotency_key, :attributes, :attachments

    def initialize(entry)
      @raw = entry.raw
      raise InvalidMessage, "Message exceeds 40 MB." unless raw
      unless raw.match?(/\A[!-9;-~]+:[^\r\n]*/) && raw.match?(/\r?\n\r?\n/)
        raise InvalidMessage, "Message headers are incomplete."
      end

      header_limit = raw.index(/\r?\n\r?\n/)
      raise InvalidMessage, "Message headers are too large." if header_limit > 256.kilobytes

      mail = Mail.new(raw)
      @identity = Conversation.message_id(mail.message_id)
      fingerprint = identity || archive_fingerprint(raw, header_limit)
      @idempotency_key = "gmail_mbox_#{Digest::SHA256.hexdigest(fingerprint)}"

      date = original_date(mail, entry.envelope_date)
      labels = mail.header.fields.select { |field| field.name.casecmp?("X-Gmail-Labels") }
        .flat_map { |field| clean(field.decoded).split(",") }.map(&:strip).reject(&:empty?).uniq
      labels = labels.first(100).map { |label| label.slice(0, 250) }.uniq
      flags = labels.map(&:downcase)
      sent = flags.include?("sent") && !flags.include?("draft")
      parent = Array(mail.in_reply_to).reverse_each.find { |id| Conversation.message_id(id) } ||
        Array(mail.references).reverse_each.find { |id| Conversation.message_id(id) }
      @attachments = extract_attachments(mail)
      total_bytes = raw.bytesize + attachments.sum { |attachment| attachment.bytes.bytesize }
      raise InvalidMessage, "Decoded attachments exceed 40 MB." if total_bytes - raw.bytesize > MboxReader::MAX_MESSAGE_BYTES

      text_part = mail.text_part || (!mail.multipart? && mail.mime_type.in?([nil, "text/plain"]) ? mail : nil)
      html_part = mail.html_part || (!mail.multipart? && mail.mime_type == "text/html" ? mail : nil)
      html = TemplateRenderer.clean_html(clean(Inbound.decoded(html_part)))
      text = clean(Inbound.decoded(text_part))
      text = Rails::HTML5::FullSanitizer.new.sanitize(html).strip if text.blank? && html.present?
      @attributes = {
        idempotency_key: idempotency_key, direction: sent ? "outbound" : "inbound", state: sent ? "sent" : "inbox",
        from_address: clean(Array(mail.from).first).slice(0, 254),
        to_addresses: addresses(mail.to), cc_addresses: addresses(mail.cc), bcc_addresses: addresses(mail.bcc),
        subject: clean(mail.subject).gsub(/[\r\n]+/, " ").slice(0, 200), text_body: text, html_body: html,
        message_id: identity || "#{idempotency_key}@import.lightek", in_reply_to: Conversation.message_id(parent),
        imported_labels: labels, starred: flags.include?("starred"), junk: flags.include?("spam"),
        trashed: flags.include?("trash"), archived: !flags.include?("inbox") && !sent,
        created_at: date, read_at: flags.include?("unread") ? nil : date, bytesize: total_bytes
      }
    rescue Mail::Field::ParseError, Mail::UnknownEncodingType, ArgumentError, EncodingError => error
      raise InvalidMessage, "Message headers or encoding could not be read.", cause: error
    end

    def duplicate?(messages)
      messages.exists?(idempotency_key: idempotency_key) ||
        (identity && messages.exists?(message_id: [identity, "<#{identity}>"]))
    end

    private

    def archive_fingerprint(raw, header_limit)
      headers = raw.byteslice(0, header_limit).gsub(/^X-Gmail-Labels:[^\r\n]*(?:\r?\n[ \t]+[^\r\n]*)*(?:\r?\n|\z)/i, "")
      headers.gsub("\r\n", "\n").chomp + "\n\n" + raw.byteslice(header_limit..).sub(/\A\r?\n\r?\n/, "").gsub("\r\n", "\n").rstrip
    end

    def addresses(value)
      Array(value).first(1000).map { |address| clean(address).slice(0, 254) }
    end

    def clean(value)
      text = value.to_s
      text = text.dup.force_encoding(Encoding::UTF_8) if text.encoding == Encoding::BINARY
      text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace).delete("\0")
    end

    def original_date(mail, from_line)
      date = mail.date&.to_time
      date ||= begin
        DateTime.parse(from_line).to_time
      rescue Date::Error
        nil
      end
      raise InvalidMessage, "Date header and MBOX date could not be read." unless date && date.year.between?(1, 9999)

      date.utc
    end

    def extract_attachments(mail)
      files = mail.attachments
      raise InvalidMessage, "Message contains more than 40 attachments." if files.size > MAX_ATTACHMENTS

      files.map do |file|
        filename = File.basename(clean(file.filename).tr("\\", "/")).delete("\r\n").slice(0, 180).presence || "attachment"
        Attachment.new(filename: filename, content_type: file.mime_type.presence || "application/octet-stream", bytes: file.decoded)
      end
    end
  end
end
