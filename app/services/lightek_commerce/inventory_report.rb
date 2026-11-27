# frozen_string_literal: true

require 'csv'

module LightekCommerce
  class InventoryReport
    class Invalid < StandardError; end

    FILTERS = %i[stock threshold lookup include_drafts].freeze
    STOCK_OPTIONS = [['Low or out of stock', 'attention'], ['Low stock', 'low'],
      ['Out of stock', 'out'], ['All tracked inventory', 'all']].freeze
    MAX_EXPORT_ROWS = 10_000
    COLUMNS = %w[product_id variant_id product_name variant_name sku available_quantity publication].freeze

    attr_reader :stock, :threshold, :lookup

    def initialize(site:, filters:)
      @stock = filters[:stock].presence || 'attention'
      unless STOCK_OPTIONS.any? { |_, value| value == @stock }
        raise Invalid, 'Choose a valid stock filter.'
      end

      value = filters[:threshold].presence || '5'
      unless value.to_s.match?(/\A(?:0|[1-9][0-9]{0,5})\z/)
        raise Invalid, 'Enter a low-stock threshold from 0 to 999,999.'
      end
      @threshold = value.to_i
      @lookup = filters[:lookup].to_s.strip
      raise Invalid, 'Search using 120 characters or fewer.' if @lookup.length > 120

      @include_drafts = filters[:include_drafts] == '1'
      @products = Product.where(site: site)
      @products = @products.where(published: true) unless include_drafts?
    end

    def include_drafts? = @include_drafts

    def rows(limit:, adjustable: false)
      catalog = adjustable ? @products.where.not(product_type: 'lightek_instance') : @products
      active = ProductVariant.where(active: true)
      products = catalog.where(track_inventory: true).where.not(id: active.select(:product_id))
        .select('id AS product_id, NULL AS variant_id, name AS product_name, NULL AS variant_name, sku, inventory_quantity, published, updated_at AS inventory_updated_at')
      variants = active.joins(:product).merge(catalog).select(
        'lightek_commerce_products.id AS product_id, lightek_commerce_product_variants.id AS variant_id, ' \
        'lightek_commerce_products.name AS product_name, lightek_commerce_product_variants.name AS variant_name, ' \
        'lightek_commerce_product_variants.sku AS sku, lightek_commerce_product_variants.inventory_quantity AS inventory_quantity, ' \
        'lightek_commerce_products.published AS published, lightek_commerce_product_variants.updated_at AS inventory_updated_at'
      )
      relation = Product.unscoped.from("(#{products.to_sql} UNION ALL #{variants.to_sql}) AS stock_rows")
        .select('stock_rows.*')
      relation = case stock
      when 'attention' then relation.where('inventory_quantity <= ?', threshold)
      when 'low' then relation.where('inventory_quantity > 0 AND inventory_quantity <= ?', threshold)
      when 'out' then relation.where('inventory_quantity = 0')
      else relation
      end
      if lookup.present?
        pattern = "%#{Product.sanitize_sql_like(lookup.downcase, '!')}%"
        relation = relation.where("LOWER(product_name) LIKE :value ESCAPE '!' OR " \
          "LOWER(variant_name) LIKE :value ESCAPE '!' OR LOWER(sku) LIKE :value ESCAPE '!'", value: pattern)
      end
      sql = relation.order(Arel.sql('inventory_quantity ASC, product_id ASC, variant_id ASC')).limit(limit).to_sql
      Product.with_connection { |connection| connection.select_all(sql).to_a }
    end

    def csv
      results = rows(limit: MAX_EXPORT_ROWS + 1)
      raise Invalid, 'Narrow your filters to export 10,000 inventory rows or fewer.' if results.size > MAX_EXPORT_ROWS

      CSV.generate do |output|
        output << COLUMNS
        results.each do |row|
          output << [row['product_id'], row['variant_id'], safe_text(row['product_name']), safe_text(row['variant_name']),
            safe_text(row['sku']), row['inventory_quantity'], publication(row)]
        end
      end
    end

    def adjustment_csv
      results = rows(limit: InventoryAdjustment::MAX_ROWS + 1, adjustable: true)
      if results.size > InventoryAdjustment::MAX_ROWS
        raise Invalid, "Narrow your filters to #{InventoryAdjustment::MAX_ROWS} inventory rows or fewer."
      end

      CSV.generate do |output|
        output << InventoryAdjustment::COLUMNS
        results.each do |row|
          output << [row['product_id'], row['variant_id'], safe_text(row['product_name']), safe_text(row['variant_name']),
            safe_text(row['sku']), row['inventory_quantity'], InventoryAdjustment.snapshot_version(row['inventory_updated_at']), nil]
        end
      end
    end

    def publication(row)
      ActiveModel::Type::Boolean.new.cast(row['published']) ? 'Published' : 'Draft'
    end

    private

    def safe_text(value)
      value.to_s.match?(/\A(?:[[:space:]]*[=+@-]|[\t\r\n])/) ? "'#{value}" : value
    end
  end
end
