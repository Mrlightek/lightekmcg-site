require "csv"

module LightekMail
  module TeamMigrationMapping
    HEADERS = %w[source_email destination_email].freeze
    MAX_ROWS = 100
    MAX_CSV_BYTES = 64.kilobytes
    ADDRESS = /\A[^\s<>@,;]+@(?:[a-z0-9-]+\.)+[a-z]{2,63}\z/i

    module_function

    def create!(actor:, name:, upload:)
      workspace = TeamMigration.workspace_for!(actor)
      pairs = parse(upload)
      destinations = Account.mailboxes.where(user_id: workspace.roster.select(:id),
        address: pairs.map(&:last)).index_by(&:address)

      TeamMigration.transaction do
        migration = TeamMigration.create!(employer: actor, name: name.to_s.strip)
        pairs.each_with_index do |(source, destination), index|
          account = destinations[destination]
          unless account
            raise ArgumentError, "CSV row #{index + 2} must point to an existing mailbox owned by an active workspace member."
          end

          migration.mailboxes.create!(source_address: source, destination_address: destination, account: account,
            mailbox_user_id: account.user_id)
        end
        migration
      end
    end

    def parse(upload)
      raise ArgumentError, "Choose a CSV mapping file." unless upload.respond_to?(:tempfile)

      utf8 = upload.tempfile.read(MAX_CSV_BYTES + 1).to_s.force_encoding(Encoding::UTF_8)
      unless utf8.valid_encoding? && utf8.bytesize.between?(1, MAX_CSV_BYTES)
        raise ArgumentError, "The CSV must be a nonempty UTF-8 file up to 64 KB."
      end

      table = CSV.parse(utf8.delete_prefix("\uFEFF"), headers: true, skip_blanks: true)
      unless table.headers == HEADERS && table.size.between?(1, MAX_ROWS)
        raise ArgumentError, "Use source_email,destination_email headers and between 1 and 100 mailbox rows."
      end

      pairs = table.map.with_index(2) do |row, index|
        addresses = row.fields.map { |field| field.to_s.strip.downcase }
        unless addresses.size == 2 && addresses.all? { |value| value.bytesize <= 254 && ADDRESS.match?(value) }
          raise ArgumentError, "CSV row #{index} needs one source and one destination email address."
        end
        addresses
      end
      if pairs.transpose.any? { |addresses| addresses.uniq.size != addresses.size }
        raise ArgumentError, "Each source and each destination may appear only once in a migration."
      end

      pairs
    rescue CSV::MalformedCSVError
      raise ArgumentError, "The mailbox mapping is not a valid CSV."
    end
  end
end
