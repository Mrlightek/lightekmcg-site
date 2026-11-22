require 'zip'
require 'nokogiri'
require 'digest'

module NevaehOs
  module DcpPackage
    MAX_BYTES = 20 * 1024**3
    XML_LIMIT = 2 * 1024**2

    module_function

    def inspect_file(path)
      Zip::File.open(path) do |archive|
        entries = archive.entries
        if entries.size > 2_000 || entries.sum(&:size) > MAX_BYTES || entries.any? { |entry| unsafe?(entry) }
          raise ArgumentError, 'The DCP archive contains unsafe paths or exceeds the package limits.'
        end
        names = entries.reject(&:directory?).map(&:name)
        raise ArgumentError, 'Duplicate archive entry.' unless names.uniq.size == names.size

        roots = {}
        archive_entries = entries.reject(&:directory?)
        archive_entries.each do |entry|
          base = File.basename(entry.name)
          next unless base.match?(/\A(?:ASSETMAP(?:\.XML)?|[\w.-]+\.xml)\z/i) && entry.size <= XML_LIMIT

          xml = entry.get_input_stream { |stream| stream.read(XML_LIMIT + 1) }
          next if xml.bytesize > XML_LIMIT || xml.match?(/<!DOCTYPE|<!ENTITY/i)

          document = Nokogiri::XML(xml) { |config| config.strict.nonet }
          root = document.root&.name
          roots[root] ||= [entry.name, document] if %w[AssetMap PackingList CompositionPlaylist].include?(root)
        rescue Nokogiri::XML::SyntaxError
          next
        end
        unless %w[AssetMap PackingList CompositionPlaylist].all? { |type| roots.key?(type) } &&
            names.any? { |name| name.end_with?('.mxf', '.MXF') }
          raise ArgumentError, 'Include an AssetMap, Packing List, Composition Playlist, and MXF tracks.'
        end

        map_name, map = roots.fetch('AssetMap')
        references = map.xpath("//*[local-name()='Chunk']/*[local-name()='Path']").map { |node| node.text.strip }
        directory = File.dirname(map_name)
        unless references.any? && references.all? { |name| names.include?(directory == '.' ? name : "#{directory}/#{name}") }
          raise ArgumentError, 'At least one DCP asset listed in the AssetMap is missing.'
        end
      end
      Digest::SHA256.file(path).hexdigest
    rescue Zip::Error
      raise ArgumentError, 'Upload a valid ZIP archive of the theater DCP.'
    end

    def unsafe?(entry)
      name = entry.name
      entry.symlink? || name.start_with?('/') || name.include?('\\') || name.include?(':') ||
        name.split('/').any? { |part| part.empty? || %w[. ..].include?(part) }
    end
  end
end
