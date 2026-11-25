# frozen_string_literal: true

require "stringio"
require "zip"

module LightekDesign
  class ThemePackage
    STARTER_FILES = %w[index.html store.html theme.css README.md].freeze
    MAX_ARCHIVE_BYTES = 6 * 1024 * 1024
    MAX_ENTRIES = 32
    MAX_PAGES = 10
    FILE_NAME = /\A[a-z0-9][a-z0-9_.-]{0,100}\.(?:html?|css)\z/i

    def self.starter
      Zip::OutputStream.write_buffer do |archive|
        STARTER_FILES.each do |name|
          archive.put_next_entry("lightek-theme-starter/#{name}")
          archive.write(File.binread(Rails.root.join("config/lightek_designs/theme_kit", name)))
        end
      end.string
    end

    def self.read!(upload)
      unless upload.respond_to?(:original_filename) && upload.original_filename.to_s.match?(/\.zip\z/i)
        raise ArgumentError, "Choose a ZIP containing your HTML pages and shared CSS."
      end

      upload.rewind
      bytes = upload.read(MAX_ARCHIVE_BYTES + 1)
      raise ArgumentError, "Choose a theme ZIP up to 6 MB." if bytes.blank? || bytes.bytesize > MAX_ARCHIVE_BYTES

      read_entries!(Zip::File.open_buffer(bytes))
    rescue Zip::Error, Zlib::Error, EOFError
      raise ArgumentError, "This ZIP could not be read. Export a new ZIP with the HTML and CSS files."
    end

    def self.read_entries!(archive)
      raise ArgumentError, "This ZIP has too many entries." if archive.entries.size > MAX_ENTRIES

      entries = archive.entries.filter_map do |entry|
        parts = entry.name.delete_suffix("/").split("/", -1)
        unsafe = entry.name.include?("\\") || parts.any? { |part| part.in?(["", ".", ".."]) } || entry.symlink?
        raise ArgumentError, "Use plain files and a single folder inside the ZIP." if unsafe
        next if entry.directory? || parts.first == "__MACOSX" || parts.last.in?(%w[.DS_Store README.md README.txt])

        unless parts.size <= 2 && parts.last.match?(FILE_NAME) && entry.file?
          raise ArgumentError, "Include only HTML pages and one CSS file. Use hosted URLs for images and media."
        end
        [entry, parts]
      end
      folders = entries.map { |_, parts| parts[0...-1] }.uniq
      raise ArgumentError, "Keep all HTML and CSS files together in one folder." if folders.size > 1

      names = entries.map { |_, parts| parts.last.downcase }
      raise ArgumentError, "Give each HTML and CSS file a unique filename." unless names.uniq == names

      styles, pages = entries.partition { |_, parts| File.extname(parts.last).casecmp?(".css") }
      raise ArgumentError, "Include 1–10 HTML pages and at most one CSS file." unless pages.size.between?(1, MAX_PAGES) && styles.size <= 1

      stylesheet, path = styles.first
      {
        files: pages.map { |entry, parts| read_entry!(entry, parts.last) },
        css_file: stylesheet && read_entry!(stylesheet, path.last)
      }
    end

    def self.read_entry!(entry, name)
      limit = HtmlDocument::MAX_BYTES
      raise ArgumentError, "#{name} exceeds 500 KB." if entry.size > limit

      value = entry.get_input_stream { |stream| stream.read(limit + 1).to_s }
      raise ArgumentError, "#{name} exceeds 500 KB." if value.bytesize > limit

      Upload.new(value, name.encode(Encoding::UTF_8))
    end

    class Upload < StringIO
      attr_reader :original_filename

      def initialize(content, filename)
        super(content)
        @original_filename = filename
      end
    end

    private_class_method :read_entries!, :read_entry!
  end
end
