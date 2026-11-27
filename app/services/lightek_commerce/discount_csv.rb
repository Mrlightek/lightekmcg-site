# frozen_string_literal: true

require 'csv'

module LightekCommerce
  class DiscountCSV
    class Invalid < StandardError; end

    ORIGINAL_HEADERS = %w[code name kind amount minimum_cents active combinable starts_at ends_at usage_limit buyer_limit product collection].freeze
    HEADERS = (ORIGINAL_HEADERS + %w[qualifying_product qualifying_collection buy_quantity get_quantity reward_type applications_per_order]).freeze
    MAX_ROWS = 500
    MAX_BYTES = 256.kilobytes

    def self.import!(site, content)
      raise Invalid, 'Choose a UTF-8 CSV file up to 256 KB.' if content.bytesize > MAX_BYTES || !content.valid_encoding?

      records = CSV.parse(content.delete_prefix("\uFEFF"), headers: true, skip_blanks: true)
      raise Invalid, 'Use the column headings from the exported CSV.' unless [HEADERS, ORIGINAL_HEADERS].include?(records.headers)
      raise Invalid, "Include 1 to #{MAX_ROWS} codes per file." unless records.size.between?(1, MAX_ROWS)

      Discount.transaction do
        records.each_with_index do |row, index|
          Discount.create!(attributes_for(site, row).merge(site: site))
        rescue Invalid => error
          raise Invalid, "Row #{index + 2}: #{error.message}"
        rescue ActiveRecord::RecordInvalid => error
          raise Invalid, "Row #{index + 2}: #{error.record.errors.full_messages.to_sentence}"
        end
      end
      records.size
    rescue CSV::MalformedCSVError
      raise Invalid, 'The CSV could not be read. Check the format and try again.'
    rescue ActiveRecord::RecordNotUnique
      raise Invalid, 'A code already exists. The import was rolled back.'
    end

    def self.export(site)
      CSV.generate do |csv|
        csv << HEADERS
        Discount.where(site: site).where.not(code: nil).includes(:target_product, :target_collection, :qualifying_product, :qualifying_collection).find_each do |rule|
          csv << [safe_cell(rule.code), safe_cell(rule.name), rule.kind, rule.amount, rule.minimum_cents,
            rule.active?, rule.combinable?, rule.starts_at&.utc&.iso8601, rule.ends_at&.utc&.iso8601,
            rule.usage_limit, rule.buyer_limit, safe_cell(rule.target_product&.slug), safe_cell(rule.target_collection&.slug),
            safe_cell(rule.qualifying_product&.slug), safe_cell(rule.qualifying_collection&.slug),
            rule.buy_quantity, rule.get_quantity, rule.reward_type, rule.applications_per_order]
        end
      end
    end

    def self.attributes_for(site, row)
      raise Invalid, 'The number of columns does not match the headings.' if row.headers.any?(&:nil?)

      values = row.to_h
      code = Discount.normalize(plain_cell(values.fetch('code')))
      raise Invalid, 'A discount code is required.' if code.blank?

      {code: code, name: plain_cell(values.fetch('name')), kind: values.fetch('kind'),
        amount: integer(values, 'amount'), minimum_cents: integer(values, 'minimum_cents') || 0,
        usage_limit: integer(values, 'usage_limit'), buyer_limit: integer(values, 'buyer_limit'),
        active: boolean(values, 'active', default: false), combinable: boolean(values, 'combinable', default: false),
        starts_at: timestamp(values, 'starts_at'), ends_at: timestamp(values, 'ends_at'),
        qualifying_product: target(Product, site, plain_cell(values['qualifying_product'])),
        qualifying_collection: target(Collection, site, plain_cell(values['qualifying_collection'])),
        buy_quantity: integer(values, 'buy_quantity'), get_quantity: integer(values, 'get_quantity'),
        reward_type: values['reward_type'].presence, applications_per_order: integer(values, 'applications_per_order'),
        target_product: target(Product, site, plain_cell(values.fetch('product'))),
        target_collection: target(Collection, site, plain_cell(values.fetch('collection')))}
    end

    def self.integer(values, key)
      raw = values[key].presence
      return nil unless raw
      raise Invalid, "#{key} must be a whole number." unless raw.match?(/\A[0-9]{1,9}\z/)

      raw.to_i
    end

    def self.boolean(values, key, default:)
      raw = values[key].presence
      return default unless raw
      raise Invalid, "#{key} must be true or false." unless %w[true false].include?(raw)

      raw == 'true'
    end

    def self.timestamp(values, key)
      raw = values[key].presence
      return nil unless raw
      raise Invalid, "#{key} must contain an ISO 8601 time with a time zone." unless raw.match?(/(?:Z|[+-]\d\d:\d\d)\z/)

      Time.iso8601(raw)
    rescue ArgumentError
      raise Invalid, "#{key} must contain a valid ISO 8601 time."
    end

    def self.target(model, site, slug)
      return if slug.blank?

      model.find_by(site: site, slug: slug) || raise(Invalid, "Target #{slug.inspect} does not exist in this store.")
    end

    def self.safe_cell(value)
      value&.match?(/\A(?:[[:space:]]*[=+@-]|['\t\r\n])/) ? "'#{value}" : value
    end

    def self.plain_cell(value)
      raw = value&.delete_prefix("'")
      safe_cell(raw) == value ? raw : value
    end
    private_class_method :attributes_for, :integer, :boolean, :timestamp, :target, :safe_cell, :plain_cell
  end
end
