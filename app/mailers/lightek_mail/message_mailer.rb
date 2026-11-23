module LightekMail
  class MessageMailer < ActionMailer::Base
    layout false
    def outbound(record, auto_reply: false)
      calendar = nil
      record.attachments.each do |file|
        if record.idempotency_key.to_s.start_with?(LightekWorkspace::ExternalInvitation::MESSAGE_PREFIX) &&
            file.filename.to_s == 'meeting.ics' && file.content_type.start_with?('text/calendar')
          calendar = file.download
        else
          attachments[file.filename.to_s] = {mime_type: file.content_type, content: file.download}
        end
      end
      headers["Auto-Submitted"] = "auto-replied" if auto_reply
      headers["X-Auto-Response-Suppress"] = "All" if auto_reply
      headers["Message-ID"] = "<#{record.message_id}>"
      headers["In-Reply-To"] = record.in_reply_to if record.in_reply_to.present?
      references = Conversation.references(record.account, record)
      headers["References"] = references.map { |id| "<#{id}>" }.join(" ") if references.any?
      sender = Mail::Address.new(record.from_address)
      sender.display_name = record.account.display_name.to_s.delete("\r\n")
      outgoing = mail(from: sender.format, to: record.to_addresses, cc: record.cc_addresses, bcc: record.bcc_addresses, subject: record.subject, delivery_method: :smtp, delivery_method_options: Transport.settings) do |format|
        format.text { render plain: record.text_body.to_s }
        format.html { render html: record.html_body.to_s.html_safe } if record.html_body.present?
      end
      if calendar
        method = calendar[/^METHOD:(REQUEST|CANCEL)\r?$/, 1]
        outgoing.part(content_type: "text/calendar; method=#{method}; charset=UTF-8", content_disposition: 'inline',
          body: calendar)
      end
      message.perform_deliveries = true
      message.raise_delivery_errors = true
    end
  end
end
