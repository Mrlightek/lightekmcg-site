# frozen_string_literal: true

module LightekCommerce
  class ReturnExchanges
    class Invalid < StandardError; end

    def self.options(order, item, record)
      return [] unless item && record.status == 'received' && record.refund_fee_cents.zero?
      return [] unless ReturnRefunds.amount_for(order, item, record) && item.product&.site_id == order.site_id

      product = item.product
      return [] unless product.published? && product.product_type == 'physical' && product.billing_interval == 'one_time'

      variants = product.variants.where(active: true)
      if variants.exists?
        variants.where(price_cents: item.unit_price_cents).where('inventory_quantity >= ?', record.quantity)
          .order(:id).limit(100).pluck(:name, :id)
      elsif product.track_inventory? && product.price_cents == item.unit_price_cents && product.inventory_quantity >= record.quantity
        [[product.name, 'product']]
      else
        []
      end
    end

    def initialize(order:, actor:)
      @order = order
      @actor = actor
    end

    def reserve_for_buyer!(id, replacement:)
      reserve!(id, replacement: replacement, buyer_request: true)
    end

    def reserve!(id, replacement:, buyer_request: false)
      replacement = replacement.to_s
      unless replacement == 'product' || replacement.match?(/\A[1-9][0-9]{0,17}\z/)
        raise Invalid, 'Select an available replacement.'
      end

      with_return(id) do |record|
        if buyer_request
          unless @actor.id == @order.storefront_buyer_id && !@order.deleted_at?
            raise ActiveRecord::RecordNotFound
          end

          current_replacement = record.replacement_variant_id&.to_s || 'product'
          if record.active_exchange? && current_replacement == replacement
            next record
          end
        end
        raise Invalid, 'This return already has an exchange.' if record.active_exchange?
        raise Invalid, 'This return already has a refund record.' if @order.refunds.exists?(merchandise_return_id: record.id)

        item = @order.items.find(record.order_item_id)
        unless record.refund_fee_cents.zero? && ReturnRefunds.amount_for(@order, item, record)
          raise Invalid, 'Only a received, refundable return with no return fee can be exchanged.'
        end

        product = locked_product(item)
        variant = replacement == 'product' ? nil : product.variants.where(active: true).lock.find(replacement)
        target = variant || product
        valid = product.published? && product.product_type == 'physical' && product.billing_interval == 'one_time' &&
          (variant || (product.track_inventory? && !product.variants.where(active: true).exists?))
        unless valid && target.price_cents == item.unit_price_cents
          raise Invalid, 'Select an in-stock replacement with the same unit price.'
        end

        InventoryStockStates.apply_locked!(product: product, target: target, from: 'available', to: nil,
          units: record.quantity, actor: @actor, merchandise_return: record)
        record.update!(exchange_status: 'reserved', replacement_variant_id: variant&.id,
          replacement_name: variant ? "#{product.name} / #{variant.name}" : product.name)
        record
      end
    end

    def cancel!(id)
      with_return(id) do |record|
        require_reserved!(record)
        product = locked_product(@order.items.find(record.order_item_id))
        target = record.replacement_variant_id ? product.variants.lock.find(record.replacement_variant_id) : product
        InventoryStockStates.apply_locked!(product: product, target: target, from: nil, to: 'available',
          units: record.quantity, actor: @actor, merchandise_return: record)
        record.update!(exchange_status: 'canceled')
      end
    end

    def ship!(id, reference:)
      reference = reference.to_s.strip
      raise Invalid, 'Enter a shipping reference up to 120 characters.' if reference.blank? || reference.length > 120

      with_return(id) do |record|
        require_reserved!(record)
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

    def locked_product(item)
      Product.where(site_id: @order.site_id).lock.find(item.product_id)
    end

    def require_reserved!(record)
      raise Invalid, 'Only a reserved replacement can be shipped or canceled.' unless record.exchange_status == 'reserved'
    end
  end
end
