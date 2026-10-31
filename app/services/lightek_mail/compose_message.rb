require "cgi"
require "stringio"
module LightekMail
  class ComposeMessage
    MODES = %w[reply reply_all forward].freeze

    def self.subject(message, mode = "reply")
      base = message.subject.to_s.sub(/\A(?:(?:re|fw|fwd):\s*)+/i, "").presence || "(no subject)"
      "#{mode == 'forward' ? 'Fwd' : 'Re'}: #{base}".slice(0, 200)
    end

    def self.recipients(account, original, mode)
      return {to: [], cc: []} if mode == "forward"
      to = original.direction == "inbound" ? [MessageContent.new(original).reply_address] : original.to_addresses
      to = to.reject { |address| address.casecmp?(account.address) }.uniq
      cc = mode == "reply_all" ? (original.to_addresses + original.cc_addresses).reject { |address| (to + [account.address]).any? { |other| address.casecmp?(other) } }.uniq : []
      {to: to, cc: cc}
    end

    def self.uploads(account:, original:, mode:, include_attachments:, uploads:)
      result = Array(uploads)
      return result unless original && mode == "forward" && include_attachments
      raise ActiveRecord::RecordNotFound unless original.account_id == account.id
      raise ArgumentError, "Original attachments exceed the message size limit." if original.attachments.sum(&:byte_size) > Submission::MAX_BYTES
      original.attachments.each do |file|
        result << {io: StringIO.new(file.download), filename: file.filename.to_s.delete("\r\n").slice(0, 180), content_type: file.content_type, byte_size: file.byte_size}
      end
      result
    end

    def self.attributes(account:, attributes:, original: nil, mode: "reply", include_original: true)
      attrs = attributes.to_h.stringify_keys
      if attrs["template_id"].present?
        template = account.templates.find(attrs.delete("template_id"))
        values = attrs.delete("variables").to_h.stringify_keys
        rendered = TemplateRenderer.render(template.document, values)
        attrs.merge!("subject" => TemplateRenderer.interpolate(template.subject, values), "text" => rendered.fetch(:text), "html" => rendered.fetch(:html))
      end
      html = TemplateRenderer.clean_html(attrs["html"])
      text = attrs["text"].to_s
      text = MessageContent.plain_text(html) if text.blank? && html.present?
      # A quoted original alone must not turn an empty composer into a send.
      raise ArgumentError, "Write a message before saving or sending." if text.blank?
      html = MessageContent.text_html(text) if html.blank?
      if original
        raise ActiveRecord::RecordNotFound unless original.account_id == account.id
        parent_id = Conversation.message_id(original.message_id)
        attrs["in_reply_to"] = mode != "forward" && parent_id ? "<#{parent_id}>" : ""
        if include_original
          label = mode == "forward" ? "Forwarded message" : "Original message"
          metadata = "#{label}\nFrom: #{original.from_address}\nDate: #{original.created_at.strftime('%b %d, %Y at %H:%M')}\nTo: #{original.to_addresses.join(', ')}\nSubject: #{original.subject}"
          text += "\n\n#{metadata}\n\n" + original.text_body.to_s.lines.map { |line| "> #{line}" }.join
          quote = MessageContent.new(original).html.presence || MessageContent.text_html(original.text_body)
          quote_fragment = Nokogiri::HTML.fragment(quote)
          quote_fragment.css("img").remove
          html += %(<div style="margin-top:28px;border-top:1px solid #dce5e1;padding-top:20px;color:#53655e"><p style="font-size:12px">#{CGI.escapeHTML(metadata).gsub("\n", "<br>")}</p><blockquote style="border-left:3px solid #d0ded8;margin:12px 0;padding-left:16px">#{quote_fragment.to_html}</blockquote></div>)
        end
      end
      # Inline styles and table layout work in conventional desktop/mobile clients.
      attrs["html"] = %(<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f7f6;color:#24342e;font-family:Arial,sans-serif"><tr><td style="padding:28px 12px"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:680px;margin:auto;background:#ffffff;border-top:3px solid #3d8b73"><tr><td style="padding:30px;font-size:15px;line-height:1.7">#{html}</td></tr></table></td></tr></table>)
      attrs["text"] = text
      attrs
    end
  end
end
