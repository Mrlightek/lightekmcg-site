require "csv"

module LightekMail
  module TeamMigrationMapping
    HEADERS = %w[source_email destination_email].freeze
    MAX_ROWS = 100
    MAX_CSV_BYTES = 64.kilobytes
    ADDRESS = /\A[^\s<>@,;]+@(?:[a-z0-9-]+\.)+[a-z]{2,63}\z/i

    module_function

    def create!(actor:, name:, upload:, pilot: false)
      pairs = parse(upload)
      if pilot && pairs.size != 1
        raise ArgumentError, "Use one mailbox in the pilot mapping. Add the rest of the team after verification."
      end

      TeamMigration.transaction do
        migration = TeamMigration.create!(employer: actor, name: name.to_s.strip, pilot: pilot)
        add_pairs!(migration, actor, pairs)
        migration
      end
    end

    def append!(migration:, actor:, upload:)
      pairs = parse(upload)
      migration.with_lock do
        raise ArgumentError, "Verify the pilot before adding team members." if migration.pilot_in_progress?

        add_pairs!(migration, actor, pairs)
      end
    end

    def add_pairs!(migration, actor, pairs)
      raise LightekPeople::Access::Denied unless migration.employer_id == actor.id

      workspace = TeamMigration.workspace_for!(actor)
      if migration.mailboxes.count + pairs.size > MAX_ROWS
        raise ArgumentError, "A migration can contain up to 100 mailbox mappings."
      end

      destinations = Account.mailboxes.where(user_id: workspace.roster.select(:id),
        address: pairs.map(&:last)).index_by(&:address)
      sources = migration.mailboxes.pluck(:source_address).to_set
      mailbox_ids = migration.mailboxes.pluck(:account_id).to_set
      pairs.each_with_index do |(source, destination), index|
        account = destinations[destination]
        unless account
          raise ArgumentError, "CSV row #{index + 2} must point to an existing mailbox owned by an active workspace member."
        end
        unless sources.add?(source) && mailbox_ids.add?(account.id)
          raise ArgumentError, "CSV row #{index + 2} uses a source or destination already in this migration."
        end

        migration.mailboxes.create!(source_address: source, destination_address: destination, account: account,
          mailbox_user_id: account.user_id)
      end
      pairs.size
    end
    private_class_method :add_pairs!

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
