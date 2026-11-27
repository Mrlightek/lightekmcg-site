# frozen_string_literal: true

require 'csv'
require 'time'
require 'securerandom'

module LightekCommerce
  class InventoryAdjustment
    class Invalid < StandardError; end

    COLUMNS = %w[product_id variant_id product_name variant_name sku available_quantity stock_version new_available_quantity].freeze
    MAX_ROWS = 500
    MAX_BYTES = 512.kilobytes
    MAX_QUANTITY = 2_147_483_647
    Change = Struct.new(:line, :product_id, :variant_id, :expected_quantity, :version, :quantity, keyword_init: true)

    def self.snapshot_version(value)
      "stock-#{ActiveRecord::Type::DateTime.new.deserialize(value).utc.iso8601(6)}"
    end

    def self.apply!(site:, actor:, data:)
      changes = parse(data)
      batch_key = SecureRandom.uuid
      actor_name = actor.full_name.presence || "Account ##{actor.id}"
      Product.transaction do
        ids = changes.map(&:product_id).uniq
        products = Product.where(site: site, id: ids).order(:id).lock.index_by(&:id)
        variants = ProductVariant.where(product_id: products.keys, active: true)
        by_id = variants.where(id: changes.filter_map(&:variant_id)).order(:product_id, :id).lock.index_by(&:id)
        simple_ids = changes.reject(&:variant_id).map(&:product_id)
        variant_product_ids = variants.where(product_id: simple_ids).distinct.pluck(:product_id).to_set

        targets = changes.map do |change|
          product = products[change.product_id]
          unless product && product.product_type != 'lightek_instance'
            raise Invalid, "Row #{change.line} references a product that cannot be adjusted for this store."
          end

          target = if change.variant_id
            by_id[change.variant_id]&.then { |variant| variant if variant.product_id == product.id }
          elsif product.track_inventory? && !variant_product_ids.include?(product.id)
            product
          end
          raise Invalid, "Row #{change.line} no longer refers to available tracked stock." unless target
          unless target.inventory_quantity == change.expected_quantity && snapshot_version(target.updated_at) == change.version
            raise Invalid, "Stock changed since export on row #{change.line}. Download a fresh template and review the counts."
          end

          [target, product, change]
        end

        targets.count do |target, product, change|
          next false if target.inventory_quantity == change.quantity

          before_quantity = target.inventory_quantity
          target.update!(inventory_quantity: change.quantity)
          InventoryChange.create!(
            site_id: site.id, product_id: product.id, variant_id: change.variant_id,
            actor_id: actor.id, actor_name: actor_name, product_name: product.name,
            variant_name: (target.name if change.variant_id), batch_key: batch_key,
            before_quantity: before_quantity, after_quantity: change.quantity
          )
          true
        end
      end
    rescue ActiveRecord::RecordInvalid => error
      raise Invalid, error.record.errors.full_messages.to_sentence
    rescue ActiveRecord::Deadlocked
      raise Invalid, 'Another inventory transaction is in progress. Try the import again.'
    end

    def self.parse(data)
      if data.bytesize > MAX_BYTES || !data.valid_encoding?
        raise Invalid, 'Choose a UTF-8 inventory template up to 512 KB.'
      end

      rows = CSV.parse(data.delete_prefix("\uFEFF"), headers: true)
      unless rows.headers == COLUMNS && rows.size.between?(1, MAX_ROWS)
        raise Invalid, "Use the inventory template with 1 to #{MAX_ROWS} rows."
      end

      changes = rows.each_with_index.filter_map do |row, index|
        line = index + 2
        raise Invalid, "Row #{line} does not match the template header." if row.headers.any?(&:nil?)
        next if row['new_available_quantity'].blank?

        product_id = parse_id(row['product_id'], line)
        variant_id = parse_id(row['variant_id'], line) if row['variant_id'].present?
        value = row['stock_version'].to_s
        unless value.match?(/\Astock-\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z\z/)
          raise Invalid, "Row #{line} is missing its inventory snapshot. Download a fresh template."
        end

        Change.new(line: line, product_id: product_id, variant_id: variant_id,
          expected_quantity: parse_quantity(row['available_quantity'], line),
          version: value, quantity: parse_quantity(row['new_available_quantity'], line))
      end
      raise Invalid, 'Enter at least one new available quantity.' if changes.empty?
      if changes.map { |change| [change.product_id, change.variant_id] }.uniq.length != changes.length
        raise Invalid, 'List each product or variant only once per upload.'
      end

      changes
    rescue CSV::MalformedCSVError
      raise Invalid, 'The inventory CSV could not be read.'
    end

    def self.parse_id(value, line)
      raise Invalid, "Row #{line} has an invalid inventory ID." unless value.to_s.match?(/\A[1-9][0-9]{0,17}\z/)

      value.to_i
    end

    def self.parse_quantity(value, line)
      unless value.to_s.match?(/\A(?:0|[1-9][0-9]{0,9})\z/) && value.to_i <= MAX_QUANTITY
        raise Invalid, "Row #{line} must have a whole stock count from 0 to #{MAX_QUANTITY}."
      end

      value.to_i
    end

    private_class_method :parse, :parse_id, :parse_quantity
  end
end
