require "digest"
require "zip"

module LightekWorkspace
  class DriveDiscovery
    LIMIT = 100
    Match = Struct.new(:entry_id, :name, :kind, :version, :date, :file_id, :revision_id, keyword_init: true)

    def initialize(drive, query:, from:, through:)
      @drive = drive
      @query = query.to_s.strip.slice(0, 160)
      @from = parse_date(from)
      @through = parse_date(through)
      raise ArgumentError, "The end date must be on or after the start date." if @from && @through && @through < @from
    end

    def matches
      entries = @drive.entries.where(folder: false)
      files = LightekOffice::SharedFile.where(drive_entry_id: entries.select(:id))
      uploads = entries.where.not(id: files.select(:drive_entry_id))
      revisions = LightekOffice::Revision.where(file_type: LightekOffice::SharedFile.polymorphic_name, file_id: files.select(:id))

      rows = matching(uploads, :name, :created_at).pluck(:id, :name, :created_at).map do |id, name, date|
        Match.new(entry_id: id, name: name, kind: "upload", date: date)
      end
      rows.concat(matching(files, :title, :updated_at).pluck(:id, :drive_entry_id, :title, :kind, :lock_version, :updated_at).map do |id, entry_id, title, kind, version, date|
        Match.new(entry_id: entry_id, name: title, kind: kind, version: version, date: date, file_id: id)
      end)
      originals = matching(revisions, :title, :created_at).pluck(:id, :file_id, :title, :version, :created_at)
      by_id = files.where(id: originals.map { |row| row[1] }).pluck(:id, :drive_entry_id, :kind).index_by(&:first)
      rows.concat(originals.map do |id, file_id, title, version, date|
        _, entry_id, kind = by_id.fetch(file_id)
        Match.new(entry_id: entry_id, name: title, kind: kind, version: version, date: date, file_id: file_id, revision_id: id)
      end)
      rows.sort_by { |item| [item.date, item.entry_id, item.version || -1] }.reverse.first(LIMIT + 1)
    end

    def export(matches, matter:)
      raise ArgumentError, "No files matched this search." if matches.empty?
      raise ArgumentError, "Narrow the search to at most #{LIMIT} results before exporting." if matches.size > LIMIT

      bytes = 0
      manifest = {matter_id: matter.id, drive_id: @drive.id, drive_name: @drive.name, exported_at: Time.current.iso8601, files: []}
      archive = Zip::OutputStream.write_buffer do |zip|
        matches.each do |item|
          entry = @drive.entries.find(item.entry_id)
          prefix = "files/#{entry.id}"
          if item.file_id
            payload = office_payload(entry, item)
            bytes = LightekMail::DiscoveryExport.reserve(bytes, payload.bytesize)
            path = "#{prefix}/version-#{item.version}.json"
            zip.put_next_entry(path)
            zip.write(payload)
            file = {path: path, sha256: Digest::SHA256.hexdigest(payload)}
          else
            raise ArgumentError, "An upload is unavailable. No export was produced." unless entry.upload.attached?

            blob = entry.upload.blob
            bytes = LightekMail::DiscoveryExport.reserve(bytes, blob.byte_size)
            extension = File.extname(blob.filename.to_s)[/\A\.[a-zA-Z0-9]{1,12}\z/]
            file = LightekMail::DiscoveryExport.write_blob(zip, "#{prefix}/original#{extension}", blob)
          end
          manifest[:files] << file.merge(entry_id: entry.id, name: item.name, kind: item.kind,
            version: item.version, date: item.date.iso8601, historical: item.revision_id.present?)
        end
        json = JSON.pretty_generate(manifest)
        LightekMail::DiscoveryExport.reserve(bytes, json.bytesize)
        zip.put_next_entry("manifest.json")
        zip.write(json)
      end
      archive.string
    rescue ActiveStorage::FileNotFoundError
      raise ArgumentError, "An upload could not be read. No export was produced."
    end

    private

    def parse_date(value)
      return if value.blank?
      raise ArgumentError, "Use YYYY-MM-DD dates." unless /\A\d{4}-\d{2}-\d{2}\z/.match?(value.to_s)

      Date.iso8601(value)
    rescue Date::Error
      raise ArgumentError, "Use valid YYYY-MM-DD dates."
    end

    def matching(scope, name_column, date_column)
      field = scope.klass.arel_table[date_column]
      scope = scope.where(field.gteq(@from.in_time_zone)) if @from
      scope = scope.where(field.lt((@through + 1.day).in_time_zone)) if @through
      if @query.present?
        term = "%#{ActiveRecord::Base.sanitize_sql_like(@query.downcase)}%"
        scope = scope.where("LOWER(#{name_column}) LIKE ?", term)
      end
      scope.order(date_column => :desc, id: :desc).limit(LIMIT + 1)
    end

    def office_payload(entry, item)
      file = entry.office_file
      raise ActiveRecord::RecordNotFound unless file&.id == item.file_id

      record = item.revision_id ? LightekOffice::Changes.revisions(file).find(item.revision_id) : file
      {title: record.title, content: record.content, rich_text: record.rich_text?, kind: file.kind, version: item.version,
        editor: item.revision_id ? record.editor_name : LightekOffice::Changes.editor(file)}.to_json
    end
  end
end
