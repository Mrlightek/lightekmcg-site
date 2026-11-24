require "csv"
require "digest"

module LightekMail
  module ContactImport
    MAX_BYTES = 2.megabytes
    MAX_ROWS = 2_000
    LIFETIME = 30.minutes
    EMAIL_COLUMN = /\Ae-?mail \d+ - value\z/
    PHONE_COLUMN = /\Aphone \d+ - value\z/
    NAME_COLUMNS = ["first name", "middle name", "last name"].freeze
    LEGACY_NAME_COLUMNS = ["given name", "additional name", "family name"].freeze

    module_function

    def preview!(account:, upload:, team_mailbox: nil)
      contacts, invalid = parse(upload)
      account.with_lock do
        ContactPreview.where("expires_at <= ?", Time.current).delete_all
        ContactPreview.where(account: account).delete_all
        ContactPreview.create!(account: account, team_mailbox: team_mailbox, contacts: contacts, invalid_rows: invalid,
          expires_at: LIFETIME.from_now)
      end
    end

    def classify(account, contacts)
      book = Contact.for_mailbox(account).pluck(:import_key, :emails, :source_emails)
      keys = book.map(&:first).to_set
      emails = book.flat_map { |_, current, original| current + original }.map(&:downcase).to_set
      contacts.map do |contact|
        key = contact.fetch("import_key")
        addresses = contact.fetch("emails").map(&:downcase)
        exists = keys.include?(key) || addresses.any? { |email| emails.include?(email) }
        unless exists
          keys.add(key)
          emails.merge(addresses)
        end
        [contact, exists]
      end
    end

    def apply!(account, preview)
      account.with_lock do
        preview.reload
        if preview.expires_at <= Time.current || preview.account_id != account.id
          raise ArgumentError, "This preview expired. Upload the CSV again."
        end

        created = 0
        skipped = 0
        classify(account, preview.contacts).each do |contact, duplicate|
          if duplicate
            skipped += 1
          else
            Contact.for_mailbox(account).create!(contact.merge("source_emails" => contact.fetch("emails")))
            created += 1
          end
        end
        if preview.team_mailbox
          preview.team_mailbox.update!(
            contacts_imported_at: created + skipped > 0 ? Time.current : preview.team_mailbox.contacts_imported_at,
            contacts_import_result: {imported: created, skipped: skipped, unreadable: preview.invalid_rows}
          )
        end
        preview.destroy!
        [created, skipped]
      end
    end

    def parse(upload)
      raise ArgumentError, "Choose a Google Contacts CSV file." unless upload.respond_to?(:tempfile)

      source = upload.tempfile.read(MAX_BYTES + 1).to_s.force_encoding(Encoding::UTF_8)
      unless source.valid_encoding? && source.bytesize.between?(1, MAX_BYTES) && !source.include?("\0")
        raise ArgumentError, "Use a UTF-8 CSV up to 2 MB."
      end

      table = CSV.parse(source.delete_prefix("\uFEFF"), headers: true, skip_blanks: true,
        header_converters: ->(header) { header.to_s.strip.downcase })
      headers = table.headers.compact
      supported = headers.intersect?(NAME_COLUMNS + LEGACY_NAME_COLUMNS + %w[name email phone]) ||
        headers.any? { |header| EMAIL_COLUMN.match?(header) || PHONE_COLUMN.match?(header) }
      unless supported && headers.uniq.size == headers.size && table.size.between?(1, MAX_ROWS)
        raise ArgumentError, "Use a Google Contacts export with unique headers and 1–2,000 contact rows."
      end

      contacts = table.filter_map do |row|
        name = full_name(row)
        emails = field_values(row, EMAIL_COLUMN, "email")
        phones = field_values(row, PHONE_COLUMN, "phone")
        labels = [row["labels"], row["group membership"]].compact.flat_map { |value| value.split(/\s*:::\s*/) }
        fields = normalize(name: name, emails: emails, phones: phones, labels: labels)
        addresses = fields.fetch("emails").map(&:downcase).sort
        identity = addresses.empty? ? [fields.fetch("name").downcase, fields.fetch("phones").sort] : addresses
        fields.merge("import_key" => Digest::SHA256.hexdigest(identity.to_json))
      rescue ArgumentError
        nil
      end
      [contacts, table.size - contacts.size]
    rescue CSV::MalformedCSVError
      raise ArgumentError, "The file is not a valid CSV."
    end

    def normalize(name:, emails:, phones:, labels:)
      name = name.to_s.strip
      emails = clean_list(emails)
      phones = clean_list(phones)
      labels = clean_list(labels)
      emails = emails.uniq(&:downcase)
      if name.length > 200 || name.match?(/[[:cntrl:]]/) || emails.any? { |value| !Contact.valid_email?(value) } ||
          [emails, phones, labels].any? { |values| values.size > 25 || values.any? { |value| value.length > 254 || value.match?(/[[:cntrl:]]/) } } ||
          (name.empty? && emails.empty? && phones.empty?)
        raise ArgumentError, "Enter a name, email address, or phone number using valid contact details."
      end

      {"name" => name, "emails" => emails, "phones" => phones, "labels" => labels}
    end

    def clean_list(values)
      values.map { |value| value.to_s.strip }.reject(&:empty?).uniq
    end

    def field_values(row, pattern, direct_header)
      row.filter_map { |header, value| value if header == direct_header || pattern.match?(header.to_s) }
    end

    def full_name(row)
      return row["name"] if row["name"].present?

      values = NAME_COLUMNS.filter_map { |column| row[column].to_s.strip.presence }
      values = LEGACY_NAME_COLUMNS.filter_map { |column| row[column].to_s.strip.presence } if values.empty?
      [row["name prefix"], *values, row["name suffix"]].filter_map { |value| value.to_s.strip.presence }.join(" ")
    end
  end
end
