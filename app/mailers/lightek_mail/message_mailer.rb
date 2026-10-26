module LightekMail
  class MessageMailer < ActionMailer::Base
    layout false
    def outbound(record, auto_reply: false)
      record.attachments.each { |file| attachments[file.filename.to_s] = {mime_type: file.content_type, content: file.download} }
      headers["Auto-Submitted"] = "auto-replied" if auto_reply
      headers["X-Auto-Response-Suppress"] = "All" if auto_reply
      headers["Message-ID"] = "<#{record.message_id}>"
      headers["In-Reply-To"] = record.in_reply_to if record.in_reply_to.present?
      mail(from: record.from_address, to: record.to_addresses, subject: record.subject, delivery_method: :smtp, delivery_method_options: Transport.settings) do |format|
        format.text { render plain: record.text_body.to_s }
        format.html { render html: record.html_body.to_s.html_safe } if record.html_body.present?
      end
      message.perform_deliveries = true
      message.raise_delivery_errors = true
    end
  end
end
