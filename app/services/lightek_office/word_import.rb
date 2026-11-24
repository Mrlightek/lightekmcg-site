# frozen_string_literal: true

require 'erb'
require 'nokogiri'
require 'uri'
require 'zip'

module LightekOffice
  class WordImport
    MAX_UPLOAD = 5_000_000
    MAX_XML = 2_000_000
    MAX_ENTRIES = 400
    WORD_NS = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
    RELATIONSHIP_NS = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
    NAMESPACES = {'w' => WORD_NS, 'r' => RELATIONSHIP_NS}.freeze
    WORD_PART = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml'
    MARKS = {'b' => 'strong', 'i' => 'em', 'u' => 'u', 'strike' => 's', 'dstrike' => 's'}.freeze

    def self.call(bytes, filename:)
      raise ArgumentError, 'Choose a Word document ending in .docx.' unless filename.to_s.downcase.end_with?('.docx')
      raise ArgumentError, 'Choose a Word document up to 5 MB.' unless bytes.bytesize.between?(1, MAX_UPLOAD)

      converted = nil
      Zip::File.open_buffer(bytes) { |archive| converted = new(archive).content }
      converted
    rescue Zip::Error, Nokogiri::XML::SyntaxError
      raise ArgumentError, 'This Word document is damaged or uses unsupported XML.'
    end

    def initialize(archive)
      @archive = archive
      names = archive.entries.map(&:name)
      raise ArgumentError, 'This Word document has too many package entries.' if names.size > MAX_ENTRIES
      if names.any? { |name| name.match?(/vbaProject|\/embeddings\/|\/activeX\//i) }
        raise ArgumentError, 'Word documents with macros or embedded objects are unsupported.'
      end
    end

    def content
      types = read_xml('[Content_Types].xml', required: true)
      main = types.xpath("//*[local-name()='Override']").find { |part| part['PartName'] == '/word/document.xml' }
      raise ArgumentError, 'This package does not contain an ordinary Word document.' unless main&.[]('ContentType') == WORD_PART

      document = read_xml('word/document.xml', required: true)
      body = document.at_xpath('/w:document/w:body', NAMESPACES)
      raise ArgumentError, 'This Word document has no supported document body.' unless body

      @links = hyperlinks
      @styles = styles
      @numbering = numbering
      Document.prepare!(blocks(body))
    end

    private

    def read_xml(path, required: false)
      entry = @archive.find_entry(path)
      raise ArgumentError, 'This Word package is missing required content.' if required && !entry
      return unless entry

      raise ArgumentError, 'Word document content is too large to import.' unless entry.size.between?(1, MAX_XML)

      source = entry.get_input_stream { |stream| stream.read(MAX_XML + 1) }.to_s
      unless source.bytesize == entry.size
        raise ArgumentError, 'Word document content exceeds the import limit or is damaged.'
      end

      document = Nokogiri::XML(source) { |options| options.strict.nonet }
      raise ArgumentError, 'Word document types and entities are unsupported.' if document.internal_subset

      document
    end

    def hyperlinks
      part = read_xml('word/_rels/document.xml.rels')
      return {} unless part

      part.xpath("//*[local-name()='Relationship']").each_with_object({}) do |relationship, links|
        next unless relationship['Type'] == "#{RELATIONSHIP_NS}/hyperlink" && relationship['TargetMode'] == 'External'

        target = relationship['Target']
        links[relationship['Id']] = target if safe_link?(target)
      end
    end

    def safe_link?(value)
      target = URI.parse(value.to_s)
      (%w[http https].include?(target.scheme) && target.host && !target.userinfo) ||
        (target.is_a?(URI::MailTo) && target.to.present?)
    rescue URI::Error
      false
    end

    def styles
      part = read_xml('word/styles.xml')
      return {} unless part

      part.xpath('/w:styles/w:style', NAMESPACES).to_h do |style|
        id = style.attribute_with_ns('styleId', WORD_NS)&.value
        [id, attribute(style, './w:name')]
      end
    end

    def numbering
      part = read_xml('word/numbering.xml')
      return {} unless part

      definitions = part.xpath('/w:numbering/w:abstractNum', NAMESPACES).to_h do |definition|
        id = definition.attribute_with_ns('abstractNumId', WORD_NS)&.value
        levels = definition.xpath('./w:lvl', NAMESPACES).to_h do |level|
          [level.attribute_with_ns('ilvl', WORD_NS)&.value, attribute(level, './w:numFmt')]
        end
        [id, levels]
      end
      part.xpath('/w:numbering/w:num', NAMESPACES).to_h do |number|
        [number.attribute_with_ns('numId', WORD_NS)&.value, definitions[attribute(number, './w:abstractNumId')] || {}]
      end
    end

    def blocks(body)
      output = +''
      open_list = nil
      body.xpath('./w:p | ./w:tbl | ./w:sdt/w:sdtContent/w:p | ./w:sdt/w:sdtContent/w:tbl', NAMESPACES).each do |node|
        role = node.name == 'p' ? paragraph_role(node) : nil
        list = role&.first.in?(%w[ul ol]) ? role : nil
        if list != open_list
          output << "</#{open_list.first}>" if open_list
          output << "<#{list.first}>" if list
          open_list = list
        end

        if node.name == 'tbl'
          node.xpath('./w:tr', NAMESPACES).each do |row|
            cells = row.xpath('./w:tc', NAMESPACES).map do |cell|
              cell.xpath('.//w:p', NAMESPACES).map { |paragraph| inline(paragraph) }.join('<br>')
            end
            output << "<p>#{cells.join(' | ')}</p>"
          end
        else
          tag = list ? 'li' : role.first
          output << "<#{tag}>#{inline(node).presence || '<br>'}</#{tag}>"
        end
        raise ArgumentError, 'Keep the editable document within 64 KB.' if output.bytesize > Content::MAX_BYTES
      end
      output << "</#{open_list.first}>" if open_list
      output
    end

    def paragraph_role(node)
      style_id = attribute(node, './w:pPr/w:pStyle')
      style = (@styles[style_id] || style_id).to_s.downcase.delete(' ')
      num_id = attribute(node, './w:pPr/w:numPr/w:numId')
      level = attribute(node, './w:pPr/w:numPr/w:ilvl') || '0'
      format = @numbering.dig(num_id, level)
      return ['ul', num_id || style] if format == 'bullet' || style.start_with?('listbullet')
      return ['ol', num_id || style] if (format && format != 'none') || style.start_with?('listnumber')
      return ["h#{style[-1]}"] if style.match?(/\Aheading[123]\z/)
      return ['blockquote'] if %w[quote intensequote].include?(style)

      ['p']
    end

    def inline(node)
      node.element_children.map do |child|
        next '' unless child.namespace&.href == WORD_NS

        case child.name
        when 't' then ERB::Util.html_escape(child.text)
        when 'br', 'cr' then '<br>'
        when 'tab' then '  '
        when 'r'
          text = inline(child)
          MARKS.values.uniq.each do |tag|
            marked = MARKS.any? do |property, html_tag|
              html_tag == tag && enabled_mark?(child.at_xpath("./w:rPr/w:#{property}", NAMESPACES))
            end
            text = "<#{tag}>#{text}</#{tag}>" if marked
          end
          text
        when 'hyperlink'
          text = inline(child)
          href = @links[child.attribute_with_ns('id', RELATIONSHIP_NS)&.value]
          href ? %(<a href="#{ERB::Util.html_escape(href)}">#{text}</a>) : text
        when 'sdt', 'sdtContent', 'ins', 'smartTag', 'fldSimple' then inline(child)
        else ''
        end
      end.join
    end

    def enabled_mark?(node)
      node && !%w[0 false off none].include?(node.attribute_with_ns('val', WORD_NS)&.value)
    end

    def attribute(node, path)
      node.at_xpath(path, NAMESPACES)&.attribute_with_ns('val', WORD_NS)&.value
    end
  end
end
