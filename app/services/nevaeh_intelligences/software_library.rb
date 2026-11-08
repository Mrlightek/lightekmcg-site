# frozen_string_literal: true
require 'digest'
require 'pathname'
module NevaehIntelligences
  class SoftwareLibrary
    class Missing < StandardError; end
    MAX_BYTES = 512_000
    def initialize(root: Rails.root)
      @root = File.realpath(root)
    end
    def documents
      candidates = Dir.glob(File.join(@root, '**', '*.{md,markdown,rst,txt}'), File::FNM_EXTGLOB)
      candidates.filter_map do |path|
        relative = Pathname.new(path).relative_path_from(Pathname.new(@root)).to_s
        next if relative.split('/').any? { |part| part.start_with?('.') || %w[vendor node_modules tmp storage log coverage test spec].include?(part) }
        next unless safe_file?(path) && File.size(path) <= MAX_BYTES
        body = File.read(path, encoding: 'UTF-8').scrub
        title = body.lines.find { |line| line.match?(/\A#\s+\S/) }&.sub(/\A#\s+/, '')&.strip || File.basename(path, '.*').tr('_-', ' ')
        {id: Digest::SHA256.hexdigest(relative)[0, 24], path: relative, title: title, section: relative.split('/')[0...-1].join('/').presence || 'Project', body: body,
          modified_at: File.mtime(path), sha256: Digest::SHA256.hexdigest(body)}
      rescue Errno::ENOENT, Errno::EACCES
        nil
      end.sort_by { |entry| [entry[:section], entry[:title].downcase] }
    end
    def search(query: '', section: '')
      words = query.to_s.downcase.scan(/[\p{L}\p{N}_-]+/).first(10)
      documents.select do |doc|
        (section.blank? || doc[:section] == section) && words.all? { |word| "#{doc[:title]} #{doc[:path]} #{doc[:body]}".downcase.include?(word) }
      end
    end
    def find(id)
      documents.find { |doc| doc[:id] == id.to_s } || raise(Missing, 'Document not found')
    end
    private
    def safe_file?(path)
      return false unless File.file?(path)
      cursor = @root
      Pathname.new(path).relative_path_from(Pathname.new(@root)).each_filename do |part|
        cursor = File.join(cursor, part)
        return false if File.symlink?(cursor)
      end
      File.realpath(path).start_with?(@root + File::SEPARATOR)
    rescue Errno::ENOENT, Errno::EACCES
      false
    end
  end
end
