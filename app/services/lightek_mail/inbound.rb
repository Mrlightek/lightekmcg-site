require "digest"
module LightekMail
  class Inbound
    def self.accept!(raw:, recipients:)
      raise ArgumentError, "Inbound message is too large." if raw.bytesize > Submission::MAX_BYTES
      recipients = Submission.addresses(recipients)
      raise ArgumentError, "No provisioned recipient." unless Account.joins(:domain).where(address: recipients, enabled: true).where.not(lightek_mail_domains: {verified_at: nil}).exists?
      checksum = OpenSSL::Digest::SHA1.hexdigest(raw)
      existing = false
      inbound = ActionMailbox::InboundEmail.transaction do
        if ActionMailbox::InboundEmail.connection.adapter_name == "PostgreSQL"
          ActionMailbox::InboundEmail.connection.execute("SELECT pg_advisory_xact_lock(#{checksum[0, 7].to_i(16)})")
        end
        inbound = ActionMailbox::InboundEmail.find_by(message_checksum: checksum)
        existing = inbound.present?
        inbound ||= ActionMailbox::InboundEmail.create_and_extract_message_id!(raw)
        raise Submission::Unavailable, "Inbound message is being accepted. Retry shortly." unless inbound
        # The authenticated ingress supplies envelope recipients, not untrusted To/Bcc headers.
        envelope = Envelope.find_or_initialize_by(inbound_email_id: inbound.id)
        envelope.recipients = (envelope.recipients + recipients).uniq
        envelope.save!
        inbound
      end
      inbound.route_later if existing
      inbound
    end
    def self.process!(inbound)
      envelope = Envelope.find_by!(inbound_email_id: inbound.id)
      mail = inbound.mail
      raw = inbound.raw_email.download
      envelope.recipients.each do |recipient|
        account = Account.find_by(address: recipient, enabled: true)
        next unless account&.domain&.verified_at
        key = "inbound_#{Digest::SHA256.hexdigest(raw)}"
        attachments = mail.attachments
        raise ArgumentError, "Message has too many attachments." if attachments.size > 10
        storage_size = raw.bytesize + attachments.sum { |file| file.decoded.bytesize }
        saved = account.with_lock do
          next if account.messages.exists?(idempotency_key: key)
          raise Submission::Unavailable, "Mailbox storage is full." if account.messages.sum(:bytesize) + storage_size > account.storage_limit
          message = account.messages.create!(direction: "inbound", state: "inbox", from_address: mail.from&.first.to_s.slice(0, 254), to_addresses: Array(mail.to),
            subject: mail.subject.to_s.delete("\r\n").slice(0, 200), text_body: (mail.text_part || (mail.html_part ? nil : mail))&.decoded.to_s.encode("UTF-8", invalid: :replace, undef: :replace),
            html_body: TemplateRenderer.clean_html(mail.html_part&.decoded.to_s.encode("UTF-8", invalid: :replace, undef: :replace)), message_id: mail.message_id.presence || SecureRandom.uuid,
            in_reply_to: mail.in_reply_to.to_s.slice(0, 250), idempotency_key: key, bytesize: storage_size)
          message.source.attach(inbound.raw_email.blob)
          mail.attachments.first(10).each do |file|
            message.attachments.attach(io: StringIO.new(file.decoded), filename: File.basename(file.filename.to_s.presence || "attachment"), content_type: file.mime_type)
          end
          message
        end
        AutoResponder.call(account, saved, mail) if saved
      end
    end
  end
end
