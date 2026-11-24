# frozen_string_literal: true

require 'uri'
require 'zip'

module LightekOffice
  class WordExport
    CONTENT_TYPE = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    WORD_NS = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
    OFFICE_RELS = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
    PACKAGE_RELS = 'http://schemas.openxmlformats.org/package/2006/relationships'
    MIME_NS = 'http://schemas.openxmlformats.org/package/2006/content-types'

    BLOCKS = %w[blockquote div h1 h2 h3 ol p pre ul].freeze
    HEADINGS = {'h1' => 'Heading1', 'h2' => 'Heading2', 'h3' => 'Heading3'}.freeze
    MARKS = {'b' => :b, 'strong' => :b, 'em' => :i, 'i' => :i, 'u' => :underline,
      'code' => :monospace, 's' => :strike, 'del' => :strike, 'strike' => :strike}.freeze
    PART_TYPES = {'document' => 'document.main', 'styles' => 'styles', 'numbering' => 'numbering'}.freeze

    def self.call(content, rich_text:)
      new(Document.editor_html(content, rich_text: rich_text)).build
    end

    def self.filename(title)
      "#{title.to_s.parameterize.presence || 'document'}.docx"
    end

    def initialize(html)
      @nodes = Nokogiri::HTML5.fragment(html).children
      @links = {}
      @lists = []
    end

    def build
      document = word_xml(:document, 'xmlns:r' => OFFICE_RELS) do |xml|
        xml['w'].body { write_blocks(xml, @nodes) }
      end
      Zip::OutputStream.write_buffer do |archive|
        {
          '[Content_Types].xml' => content_types,
          '_rels/.rels' => relationships([['rId1', 'officeDocument', 'word/document.xml']]),
          'word/document.xml' => document,
          'word/styles.xml' => styles,
          'word/numbering.xml' => numbering,
          'word/_rels/document.xml.rels' => document_relationships
        }.each do |path, content|
          archive.put_next_entry(path)
          archive.write(content)
        end
      end.string
    end

    private

    def word_xml(root, attributes = {}, &block)
      Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
        xml['w'].public_send(root, {'xmlns:w' => WORD_NS}.merge(attributes)) { block.call(xml) }
      end.to_xml
    end

    def write_blocks(xml, nodes, depth: 0, list_item: nil)
      inline = []
      flush = lambda do
        unless inline.all? { |node| node.text? && node.text.strip.empty? }
          paragraph(xml, inline, list_item: list_item)
          list_item = nil
        end
        inline.clear
      end

      nodes.each do |node|
        unless node.element? && BLOCKS.include?(node.name)
          inline << node
          next
        end

        flush.call
        case node.name
        when 'ul', 'ol'
          if list_item
            paragraph(xml, [], list_item: list_item)
            list_item = nil
          end
          write_list(xml, node, depth)
        when 'div'
          write_blocks(xml, node.children, depth: depth, list_item: list_item)
          list_item = nil
        else
          paragraph(xml, node.children, style: HEADINGS[node.name], list_item: list_item,
            quote: node.name == 'blockquote', marks: node.name == 'pre' ? [:monospace] : [])
          list_item = nil
        end
      end

      flush.call
      paragraph(xml, [], list_item: list_item) if list_item
    end

    def write_list(xml, node, depth)
      @lists << {ordered: node.name == 'ol', indent: 720 + [depth, 8].min * 360}
      id = @lists.length
      node.element_children.select { |item| item.name == 'li' }.each do |item|
        write_blocks(xml, item.children, depth: depth + 1, list_item: id)
      end
    end

    def paragraph(xml, nodes, style: nil, list_item: nil, quote: false, marks: [])
      xml['w'].p do
        if style || list_item || quote
          xml['w'].pPr do
            xml['w'].pStyle('w:val' => style) if style
            if list_item
              xml['w'].numPr do
                xml['w'].ilvl('w:val' => 0)
                xml['w'].numId('w:val' => list_item)
              end
            end
            xml['w'].ind('w:left' => 480) if quote
          end
        end
        nodes.each { |node| write_inline(xml, node, marks) }
      end
    end

    def write_inline(xml, node, marks)
      if node.text?
        node.text.split(/(\r\n|\r|\n|\t)/).reject(&:empty?).each do |text|
          run(xml, marks) do
            case text
            when "\r\n", "\r", "\n" then xml['w'].br
            when "\t" then xml['w'].tab
            else xml['w'].t('xml:space' => 'preserve') { xml.text(text.delete("\u0000-\u0008\u000B\u000C\u000E-\u001F\uFFFE\uFFFF")) }
            end
          end
        end
      elsif node.name == 'br'
        run(xml, marks) { xml['w'].br }
      elsif node.name == 'a' && (href = safe_link(node['href']))
        id = @links[href] ||= "rId#{@links.size + 3}"
        xml['w'].hyperlink('r:id' => id) do
          node.children.each { |child| write_inline(xml, child, marks | [:link, :underline]) }
        end
      else
        mark = MARKS[node.name]
        node.children.each { |child| write_inline(xml, child, mark ? marks | [mark] : marks) }
      end
    end

    def run(xml, marks)
      xml['w'].r do
        if marks.any?
          xml['w'].rPr do
            xml['w'].rFonts('w:ascii' => 'Courier New', 'w:hAnsi' => 'Courier New') if marks.include?(:monospace)
            xml['w'].b if marks.include?(:b)
            xml['w'].i if marks.include?(:i)
            xml['w'].strike if marks.include?(:strike)
            xml['w'].color('w:val' => '0563C1') if marks.include?(:link)
            xml['w'].u('w:val' => 'single') if marks.include?(:underline)
          end
        end
        yield
      end
    end

    def safe_link(href)
      target = URI.parse(href.to_s)
      return href if %w[http https].include?(target.scheme) && target.host && !target.userinfo
      return href if target.is_a?(URI::MailTo) && target.to.present?
    rescue URI::Error
      nil
    end

    def content_types
      Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
        xml.Types('xmlns' => MIME_NS) do
          xml.Default('Extension' => 'rels', 'ContentType' => 'application/vnd.openxmlformats-package.relationships+xml')
          xml.Default('Extension' => 'xml', 'ContentType' => 'application/xml')
          PART_TYPES.each do |part, type|
            xml.Override('PartName' => "/word/#{part}.xml",
              'ContentType' => "application/vnd.openxmlformats-officedocument.wordprocessingml.#{type}+xml")
          end
        end
      end.to_xml
    end

    def document_relationships
      internal = [%w[rId1 styles styles.xml], %w[rId2 numbering numbering.xml]]
      relationships(internal + @links.map { |url, id| [id, 'hyperlink', url, 'External'] })
    end

    def relationships(entries)
      Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
        xml.Relationships('xmlns' => PACKAGE_RELS) do
          entries.each do |id, type, target, mode|
            attributes = {'Id' => id, 'Type' => "#{OFFICE_RELS}/#{type}", 'Target' => target}
            attributes['TargetMode'] = mode if mode
            xml.Relationship(attributes)
          end
        end
      end.to_xml
    end

    def styles
      word_xml(:styles) do |xml|
        xml['w'].style('w:type' => 'paragraph', 'w:styleId' => 'Normal', 'w:default' => '1') do
          xml['w'].name('w:val' => 'Normal')
          xml['w'].qFormat
        end
        HEADINGS.values.each_with_index do |style, level|
          xml['w'].style('w:type' => 'paragraph', 'w:styleId' => style) do
            xml['w'].name('w:val' => "heading #{level + 1}")
            xml['w'].basedOn('w:val' => 'Normal')
            xml['w'].next('w:val' => 'Normal')
            xml['w'].qFormat
            xml['w'].pPr { xml['w'].outlineLvl('w:val' => level) }
            xml['w'].rPr do
              xml['w'].b
              xml['w'].sz('w:val' => 36 - 4 * level)
            end
          end
        end
      end
    end

    def numbering
      word_xml(:numbering) do |xml|
        @lists.each_with_index do |list, index|
          xml['w'].abstractNum('w:abstractNumId' => index) do
            xml['w'].multiLevelType('w:val' => 'singleLevel')
            xml['w'].lvl('w:ilvl' => 0) do
              xml['w'].start('w:val' => 1)
              xml['w'].numFmt('w:val' => list[:ordered] ? 'decimal' : 'bullet')
              xml['w'].lvlText('w:val' => list[:ordered] ? '%1.' : '•')
              xml['w'].lvlJc('w:val' => 'left')
              xml['w'].pPr { xml['w'].ind('w:left' => list[:indent], 'w:hanging' => 360) }
            end
          end
        end
        @lists.each_index do |id|
          xml['w'].num('w:numId' => id + 1) { xml['w'].abstractNumId('w:val' => id) }
        end
      end
    end
  end
end
