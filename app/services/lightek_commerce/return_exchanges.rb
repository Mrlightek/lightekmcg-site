# frozen_string_literal: true

module LightekCommerce
  class ReturnExchanges
    class Invalid < StandardError; end

    def self.options(order, item, record)
      return [] unless eligible?(order, item, record) && item.product&.site_id == order.site_id

      catalog = Product.where(site_id: order.site_id, published: true, product_type: 'physical', billing_interval: 'one_time')
      original = catalog.find_by(id: item.product_id)
      original_options = original ? options_for_original(original, item, record.quantity) : []
      alternates = catalog.where.not(id: item.product_id)
      variant_options = ProductVariant.where(product_id: alternates.select(:id), active: true, price_cents: item.unit_price_cents)
        .where('inventory_quantity >= ?', record.quantity).includes(:product).order(:id).limit(100).map do |variant|
        ["#{variant.product.name} / #{variant.name}", "product:#{variant.product_id}:#{variant.id}"]
      end
      products = alternates.where(track_inventory: true, price_cents: item.unit_price_cents)
        .where('inventory_quantity >= ?', record.quantity)
        .where.not(id: ProductVariant.where(active: true).select(:product_id)).order(:id).limit(100)
      original_options + products.map { |product| [product.name, "product:#{product.id}"] } + variant_options
    end

    def self.eligible?(order, item, record)
      return false unless item && !record.active_exchange? && record.refund_fee_cents.zero?

      if record.status == 'approved'
        ReturnRefunds.available?(order, item, record) && ReturnRefunds.minimum_merchandise_amount(item, record).positive? &&
          order.total_cents > order.refunded_cents
      else
        ReturnRefunds.amount_for(order, item, record).present?
      end
    end

    def self.options_for_original(product, item, quantity)
      variants = product.variants.where(active: true)
      if variants.exists?
        variants.where(price_cents: item.unit_price_cents).where('inventory_quantity >= ?', quantity)
          .order(:id).limit(100).pluck(:name, :id)
      elsif product.track_inventory? && product.price_cents == item.unit_price_cents && product.inventory_quantity >= quantity
        [[product.name, 'product']]
      else
        []
      end
    end
    private_class_method :options_for_original

    def initialize(order:, actor:)
      @order = order
      @actor = actor
    end

    def reserve_for_buyer!(id, replacement:)
      reserve!(id, replacement: replacement, buyer_request: true)
    end

    def reserve!(id, replacement:, buyer_request: false)
      with_return(id) do |record|
        if buyer_request && (@actor.id != @order.storefront_buyer_id || @order.deleted_at?)
          raise ActiveRecord::RecordNotFound
        end

        item = @order.items.find(record.order_item_id)
        product_id, variant_id = replacement_ids(replacement, item.product_id)
        if buyer_request && record.active_exchange? &&
            [record.replacement_product_id || item.product_id, record.replacement_variant_id] == [product_id, variant_id]
          next record
        end
        raise Invalid, 'This return already has an exchange.' if record.active_exchange?
        raise Invalid, 'This return already has a refund record.' if @order.refunds.exists?(merchandise_return_id: record.id)

        unless self.class.eligible?(@order, item, record)
          raise Invalid, 'Only an approved or received return eligible for a no-fee exchange can reserve a replacement.'
        end

        product = locked_product(product_id)
        variant = product.variants.where(active: true).lock.find(variant_id) if variant_id
        target = variant || product
        valid = product.published? && product.product_type == 'physical' && product.billing_interval == 'one_time' &&
          (variant || (product.track_inventory? && !product.variants.where(active: true).exists?))
        unless valid && target.price_cents == item.unit_price_cents
          raise Invalid, 'Select an in-stock replacement with the same unit price.'
        end

        InventoryStockStates.apply_locked!(product: product, target: target, from: 'available', to: nil,
          units: record.quantity, actor: @actor, merchandise_return: record)
        record.update!(exchange_status: 'reserved', replacement_product_id: product.id, replacement_variant_id: variant&.id,
          replacement_name: variant ? "#{product.name} / #{variant.name}" : product.name)
        record
      end
    end

    def cancel!(id)
      with_return(id) { |record| cancel_locked!(record) }
    end

    # Caller holds the original order lock, including when the return itself is canceled.
    def cancel_locked!(record)
      require_reserved!(record)
      product_id = record.replacement_product_id || @order.items.find(record.order_item_id).product_id
      product = locked_product(product_id)
      target = record.replacement_variant_id ? product.variants.lock.find(record.replacement_variant_id) : product
      InventoryStockStates.apply_locked!(product: product, target: target, from: nil, to: 'available',
        units: record.quantity, actor: @actor, merchandise_return: record)
      record.update!(exchange_status: 'canceled', replacement_product_id: nil)
    end

    def ship!(id, reference:)
      reference = reference.to_s.strip
      raise Invalid, 'Enter a shipping reference up to 120 characters.' if reference.blank? || reference.length > 120

      with_return(id) do |record|
        require_reserved!(record)
        raise Invalid, 'Receive the returned items before shipping the replacement.' unless record.status == 'received'

        record.update!(exchange_status: 'shipped', exchange_shipping_reference: reference, exchange_shipped_at: Time.current)
      end
    end

    private

    def with_return(id)
      raise ActiveRecord::RecordNotFound unless id.to_s.match?(/\A[1-9][0-9]{0,17}\z/)

      @order.with_lock do
        yield MerchandiseReturn.where(order_id: @order.id).find(id)
      end
    rescue ActiveRecord::RecordInvalid => error
      raise Invalid, error.record.errors.full_messages.to_sentence
    rescue ActiveRecord::Deadlocked
      raise Invalid, 'Another stock transaction is in progress. Try again.'
    end

    def locked_product(id)
      Product.where(site_id: @order.site_id).lock.find(id)
    end

    def replacement_ids(value, original_id)
      value = value.to_s
      case value
      when 'product'
        [original_id, nil]
      when /\A[1-9][0-9]{0,17}\z/
        [original_id, value.to_i]
      when /\Aproduct:([1-9][0-9]{0,17})(?::([1-9][0-9]{0,17}))?\z/
        match = Regexp.last_match
        [match[1].to_i, match[2]&.to_i]
      else
        raise Invalid, 'Select an available replacement.'
      end
    end

    def require_reserved!(record)
      raise Invalid, 'Only a reserved replacement can be shipped or canceled.' unless record.exchange_status == 'reserved'
    end
  end
end
