require "zip"
require "zlib"
require "digest"

module LightekWorkspace
  module DriveArchive
    MAX_UPLOAD = 50.megabytes
    MAX_EXPANDED = 100.megabytes
    MAX_FILE = 25.megabytes
    MAX_ENTRIES = 500
    OFFICE_IMPORTERS = {
      ".docx" => ["document", LightekOffice::WordImport],
      ".xlsx" => ["spreadsheet", LightekOffice::ExcelImport],
      ".pptx" => ["presentation", LightekOffice::PowerpointImport]
    }.freeze

    module_function

    def preview!(drive:, folder:, actor:, upload:)
      unless upload.respond_to?(:tempfile) && File.extname(upload.original_filename).casecmp?(".zip") &&
          upload.size.between?(1, MAX_UPLOAD)
        raise ArgumentError, "Choose a ZIP archive up to 50 MB."
      end
      DriveImport.authorize!(drive, actor)
      result = nil
      blob = nil
      open(upload.tempfile.path) do |zip, paths|
        items = preview_items(zip, paths, drive, folder)
        upload.tempfile.rewind
        blob = ActiveStorage::Blob.create_and_upload!(io: upload.tempfile, filename: upload.original_filename,
          content_type: "application/zip", identify: false)
        result = drive.with_lock do
          DriveImport.authorize!(drive, actor)
          DriveImport.create!(drive: drive, folder: folder, actor: actor, filename: blob.filename.to_s, items: items, archive: blob)
        end
      end
      result
    rescue StandardError
      blob&.purge unless result&.persisted?
      raise
    end

    def open(path)
      expected_entries = validate_directory_size!(path)
      Zip::File.open(path) do |zip|
        entries = zip.entries
        raise ArgumentError, "The ZIP contains duplicate or unreadable paths." unless entries.size == expected_entries

        total = entries.reject(&:directory?).sum(&:size)
        raise ArgumentError, "Expanded archive exceeds 100 MB." if total > MAX_EXPANDED

        paths = {}
        entries.each do |entry|
          name = safe_path(entry)
          raise ArgumentError, "The ZIP contains duplicate paths." if paths.key?(name) && paths[name]

          paths[name] = entry
          parts = name.split("/")
          1.upto(parts.length - 1) { |length| paths[parts.first(length).join("/")] ||= nil }
        end
        if paths.size > MAX_ENTRIES || paths.any? { |name, entry| entry&.file? && paths.keys.any? { |other| other.start_with?("#{name}/") } }
          raise ArgumentError, "The ZIP has too many paths or a file occupies a folder path."
        end

        yield zip, paths.sort_by { |name, _| [name.count("/"), name] }.to_h
      end
    rescue Zip::Error, Zlib::Error, EOFError, IOError, EncodingError
      raise ArgumentError, "This ZIP archive could not be read."
    end

    def validate_directory_size!(path)
      File.open(path, "rb") do |file|
        file.seek([file.size - 65_557, 0].max)
        tail = file.read
        marker = tail.rindex("PK\x05\x06".b)
        bytes = tail.byteslice(marker, 22) if marker
        raise ArgumentError, "This ZIP archive could not be read." unless bytes&.bytesize == 22

        disk, first_disk, disk_entries, entries, size, offset, comment = bytes.byteslice(4..).unpack("vvvvVVv")
        unless [disk, first_disk] == [0, 0] && disk_entries == entries && entries.between?(1, MAX_ENTRIES) &&
            tail.bytesize == marker + 22 + comment && offset + size <= file.size - 22 - comment
          raise ArgumentError, "Use a single ZIP archive with 1–500 entries."
        end
        entries
      end
    end

    def safe_path(entry)
      name = entry.name.dup.force_encoding(Encoding::UTF_8).delete_suffix("/")
      segments = name.split("/", -1)
      unless name.valid_encoding? && segments.size.between?(1, 20) && !name.match?(/\\|\A[a-zA-Z]:|[[:cntrl:]]/) &&
          segments.all? { |part| part.length.between?(1, 160) && part == part.strip && !part.in?(%w[. ..]) } &&
          (entry.directory? || entry.file?) && !entry.encrypted?
        raise ArgumentError, "The ZIP contains an unsafe path, unsupported link, or encrypted entry."
      end

      name
    end

    def preview_items(zip, paths, drive, folder)
      destinations = {"" => folder}
      paths.map do |path, entry|
        directory = !entry || entry.directory?
        parent_path, name = split(path)
        type = directory ? "folder" : "download"
        message = nil
        if !directory && entry.size > MAX_FILE
          status = "skipped"
          message = "File exceeds 25 MB."
        else
          bytes = read(zip, entry) unless directory
          digest = directory ? "folder" : Digest::SHA256.hexdigest(bytes)
          receipt = receipt_for(drive, folder, path)
          target = unless destinations[parent_path] == false
            child(drive, destinations[parent_path], name) unless destinations[parent_path] == :new
          end
          if receipt.persisted?
            status = receipt.entry && receipt.digest == digest ? "duplicate" : "conflict"
            type = receipt.entry&.office_file&.kind || type unless directory
            message = status == "duplicate" ? "Already imported." : "A previous import used this path with different content."
            destinations[path] = status == "duplicate" ? receipt.entry : false if directory
          elsif destinations[parent_path] == false || target == :ambiguous || (target && (!directory || !target.folder?))
            status = "conflict"
            message = "An existing entry occupies this path or its parent."
            destinations[path] = false if directory
          elsif directory
            status = target ? "reuse" : "new"
            destinations[path] = target || :new
          else
            status = "new"
            native, message = office(bytes, name)
            type = native.fetch(:kind) if native
          end
        end
        {"path" => path, "type" => type, "status" => status, "message" => message}
      end
    end

    def split(path)
      parent, _, name = path.rpartition("/")
      [parent, name]
    end

    def child(drive, parent, name)
      matches = drive.entries.where(parent: parent, name: name).limit(2).to_a
      matches.size > 1 ? :ambiguous : matches.first
    end

    def receipt_for(drive, folder, path)
      key = Digest::SHA256.hexdigest([folder&.id, path].to_json)
      DriveImportReceipt.find_or_initialize_by(drive: drive, source_key: key)
    end

    def read(zip, entry)
      bytes = zip.get_input_stream(entry) { |input| input.read(MAX_FILE + 1) || "".b }
      unless bytes.bytesize == entry.size && bytes.bytesize <= MAX_FILE && Zlib.crc32(bytes) == entry.crc
        raise ArgumentError, "The ZIP contains an unreadable or oversized entry."
      end

      bytes
    end

    def office(bytes, name)
      kind, importer = OFFICE_IMPORTERS[File.extname(name).downcase]
      return [] unless importer

      content = importer.call(bytes, filename: name)
      [{kind: kind, title: name, content: content, rich_text: kind == "document"}]
    rescue ArgumentError => error
      [nil, "Kept as a download. #{error.message}".truncate(220)]
    end
  end
end
