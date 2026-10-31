require "mail"
require "cgi"
module LightekMail
  # HTML is always sanitized before display. Source recovery restores inline
  # formatting from messages received before the HTML renderer was upgraded.
  class MessageContent
    def initialize(message)
      @message = message
    end

    def source_mail
      return @source_mail if defined?(@source_mail)
      @source_mail = if @message.direction == "inbound" && @message.source.attached? && @message.source.byte_size <= Submission::MAX_BYTES
        Mail.read_from_string(@message.source.download)
      end
    rescue ArgumentError, EncodingError, ActiveStorage::FileNotFoundError
      @source_mail = nil
    end

    def html
      return @html if defined?(@html)
      mail = source_mail
      part = mail&.html_part || (mail if mail&.mime_type == "text/html")
      raw = part ? Inbound.decoded(part) : @message.html_body
      @html = TemplateRenderer.clean_html(raw)
    end

    def sender_name
      return @message.account.display_name if @message.direction == "outbound"
      source_mail&.[](:from)&.display_names&.first.presence || @message.from_address
    end

    def reply_address
      values = source_mail&.reply_to
      values.present? ? Submission.addresses(values).first : @message.from_address
    rescue ArgumentError
      @message.from_address
    end

    def remote_images?
      Nokogiri::HTML.fragment(html).css("img[src]").any? { |node| node["src"].to_s.start_with?("https://") }
    end

    def self.text_html(text)
      CGI.escapeHTML(text.to_s).split(/\n{2,}/).map { |paragraph| "<p>#{paragraph.gsub("\n", "<br>")}</p>" }.join
    end

    def self.plain_text(html)
      fragment = Nokogiri::HTML.fragment(html.to_s)
      fragment.css("br").each { |node| node.replace("\n") }
      fragment.css("p,div,li,h1,h2,h3,blockquote,tr").each { |node| node.add_next_sibling(Nokogiri::XML::Text.new("\n", fragment.document)) }
      fragment.text.gsub(/\n{3,}/, "\n\n").strip
    end

    def self.document(html, images: false)
      fragment = Nokogiri::HTML.fragment(TemplateRenderer.clean_html(html))
      fragment.css("a").each do |node|
        node["target"] = "_blank"
        node["rel"] = "noopener noreferrer"
      end
      fragment.css("img").each do |node|
        node.remove unless images && node["src"].to_s.start_with?("https://")
      end
      policy = "default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src #{images ? 'https:' : "'none'"}; base-uri 'none'; form-action 'none'"
      %(<html><head><meta charset="UTF-8"><meta http-equiv="Content-Security-Policy" content="#{CGI.escapeHTML(policy)}"><meta name="referrer" content="no-referrer"><style>html,body{margin:0;background:#fff;color:#24323c;font:15px/1.65 Arial,sans-serif;overflow-wrap:anywhere}body{padding:24px;box-sizing:border-box;max-width:900px;margin:0 auto}img{max-width:100%;height:auto}table{max-width:100%}pre{white-space:pre-wrap}a{color:#176b59}blockquote{margin:16px 0;padding-left:18px;border-left:3px solid #d6dfdc}@media(max-width:600px){body{padding:14px}}</style></head><body>#{fragment.to_html}</body></html>)
    end
  end
end
