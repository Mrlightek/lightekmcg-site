# frozen_string_literal: true

require 'nokogiri'
require 'zip'

module LightekOffice
  class PowerpointImport
    MAX_UPLOAD = 5_000_000
    MAX_XML = 1_000_000
    MAX_ENTRIES = 500
    PRESENTATION_NS = 'http://schemas.openxmlformats.org/presentationml/2006/main'
    DRAWING_NS = 'http://schemas.openxmlformats.org/drawingml/2006/main'
    OFFICE_RELS = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
    PACKAGE_RELS = 'http://schemas.openxmlformats.org/package/2006/relationships'
    TYPES_NS = 'http://schemas.openxmlformats.org/package/2006/content-types'
    NS = {'p' => PRESENTATION_NS, 'a' => DRAWING_NS}.freeze
    MAIN_TYPE = 'application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml'
    TITLE_TYPES = %w[title ctrTitle].freeze

    def self.call(bytes, filename:)
      raise ArgumentError, 'Choose a PowerPoint file ending in .pptx.' unless filename.to_s.downcase.end_with?('.pptx')
      raise ArgumentError, 'Choose a PowerPoint file up to 5 MB.' unless bytes.bytesize.between?(1, MAX_UPLOAD)

      source = nil
      Zip::File.open_buffer(bytes) { |archive| source = new(archive).content }
      source
    rescue Zip::Error, Nokogiri::XML::SyntaxError, EOFError, Zlib::Error
      raise ArgumentError, 'This PowerPoint file is damaged or contains unsupported XML.'
    end

    def initialize(archive)
      @archive = archive
      names = archive.entries.map(&:name)
      raise ArgumentError, 'This PowerPoint file has too many package entries.' if names.size > MAX_ENTRIES
      if names.any? { |name| name.match?(/vbaProject|\/embeddings\/|\/activeX\//i) }
        raise ArgumentError, 'PowerPoint files with macros or embedded objects are unsupported.'
      end
    end

    def content
      types = xml('[Content_Types].xml')
      main = types.xpath('/ct:Types/ct:Override', 'ct' => TYPES_NS).find { |part| part['PartName'] == '/ppt/presentation.xml' }
      raise ArgumentError, 'This package is not a standard PowerPoint presentation.' unless main&.[]('ContentType') == MAIN_TYPE

      slides = xml('ppt/presentation.xml').xpath('/p:presentation/p:sldIdLst/p:sldId', NS)
      if slides.empty? || slides.size > Content::MAX_SLIDES
        raise ArgumentError, "Choose a presentation with 1–#{Content::MAX_SLIDES} slides."
      end

      paths = slide_paths
      output = +''
      slides.each_with_index do |slide, index|
        id = slide.attribute_with_ns('id', OFFICE_RELS)&.value
        path = paths[id]
        raise ArgumentError, "Slide #{index + 1} has no supported slide part." unless path

        output << "\n---\n" unless index.zero?
        output << read_slide(path, index + 1)
        raise ArgumentError, 'Keep editable presentation text within 64 KB.' if output.bytesize > Content::MAX_BYTES
      end
      Content.validate!('presentation', output)
      output
    end

    private

    def xml(path)
      entry = @archive.find_entry(path)
      raise ArgumentError, 'This PowerPoint file is missing a required part.' unless entry
      raise ArgumentError, 'A PowerPoint part exceeds the import limit.' unless entry.size.between?(1, MAX_XML)

      data = entry.get_input_stream { |stream| stream.read(MAX_XML + 1) }.to_s
      raise ArgumentError, 'The PowerPoint part size is invalid.' unless data.bytesize == entry.size

      document = Nokogiri::XML(data) { |config| config.strict.nonet }
      raise ArgumentError, 'PowerPoint document types and entities are unsupported.' if document.internal_subset

      document
    end

    def slide_paths
      xml('ppt/_rels/presentation.xml.rels').xpath('/rel:Relationships/rel:Relationship', 'rel' => PACKAGE_RELS)
        .each_with_object({}) do |relationship, paths|
          next unless relationship['Type'] == "#{OFFICE_RELS}/slide" && relationship['TargetMode'].nil?

          path = relationship['Target'].to_s.delete_prefix('/')
          path = "ppt/#{path}" unless path.start_with?('ppt/')
          unless path.match?(%r{\Appt/slides/[A-Za-z0-9_.-]+\.xml\z}) && !paths.key?(relationship['Id'])
            raise ArgumentError, 'A PowerPoint slide relationship is invalid.'
          end

          paths[relationship['Id']] = path
        end
    end

    def read_slide(path, number)
      tree = xml(path).at_xpath('/p:sld/p:cSld/p:spTree', NS)
      raise ArgumentError, "Slide #{number} has no supported slide content." unless tree

      shapes = tree.xpath('.//p:sp[p:txBody]', NS).filter_map do |shape|
        text = shape.xpath('./p:txBody/a:p', NS).map { |paragraph| paragraph_text(paragraph) }.join("\n").strip
        next if text.empty?

        placeholder = shape.at_xpath('./p:nvSpPr/p:nvPr/p:ph', NS)
        [TITLE_TYPES.include?(placeholder&.[]('type')), text]
      end

      title_index = shapes.index { |title, _| title }
      title_index ||= 0 if shapes.any?
      heading, continuation = title_index ? shapes.delete_at(title_index).last.split("\n", 2) : ["Slide #{number}", nil]
      body = ([continuation.presence] + shapes.map(&:last)).compact.join("\n\n")
      result = [heading.rstrip, body.presence].compact.join("\n")
      if result.match?(/^---[ \t]*\r?$/)
        raise ArgumentError, "Slide #{number} contains a line of three dashes. Change that line before importing."
      end

      result
    end

    def paragraph_text(paragraph)
      paragraph.xpath('./a:r/a:t | ./a:fld/a:t | ./a:br', NS).map do |part|
        part.name == 'br' ? "\n" : part.text.gsub(/\r\n?/, "\n")
      end.join
    end
  end
end
