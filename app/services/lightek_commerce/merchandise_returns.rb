# frozen_string_literal: true

module LightekCommerce
  class MerchandiseReturns
    class Invalid < StandardError; end

    DISPOSITIONS = {
      'available' => 'Return to available stock',
      'damaged' => 'Add to damaged stock',
      'discarded' => 'Record receipt without restocking'
    }.freeze

    def self.eligible_order?(order)
      order.paid_at? && (order.fulfilled_at? || order.status == 'fulfilled') &&
        order.status.in?(%w[fulfilled partially_refunded refunded])
    end

    def self.buyer_orders(site:, buyer:)
      Order.receipt_eligible.where(site: site, storefront_buyer_id: buyer.id)
    end

    def self.buyer_order!(site:, buyer:, id:)
      raise ActiveRecord::RecordNotFound unless id.to_s.match?(/\A[1-9][0-9]{0,17}\z/)

      order = buyer_orders(site: site, buyer: buyer).find(id)
      unless eligible_order?(order) && order.items.includes(:product).any?(&:physical_for_fulfillment?)
        raise ActiveRecord::RecordNotFound
      end

      order
    end

    def self.restockable?(order, item)
      order.stock_reserved? && item.purchase_snapshot.to_h['track_inventory'] == true
    end

    def initialize(order:, actor:)
      @order = order
      @actor = actor
    end

    def request!(item_id:, quantity:, reason:, request_key:, buyer_request: false)
      unless request_key.to_s.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/)
        raise Invalid, 'Reload the order before requesting a return.'
      end
      unless quantity.to_s.match?(/\A[1-9][0-9]{0,9}\z/) && quantity.to_i <= InventoryAdjustment::MAX_QUANTITY
        raise Invalid, 'Enter a valid whole return quantity.'
      end
      raise ActiveRecord::RecordNotFound unless item_id.to_s.match?(/\A[1-9][0-9]{0,17}\z/)

      reason = reason.to_s.strip
      @order.with_lock do
        if buyer_request && (@order.storefront_buyer_id != @actor.id || @order.deleted_at?)
          raise ActiveRecord::RecordNotFound
        end
        item = @order.items.find(item_id)
        unless self.class.eligible_order?(@order) && item.physical_for_fulfillment?
          raise Invalid, 'Returns are available for fulfilled physical items.'
        end
        units = quantity.to_i
        matching = returns.find_by(request_key: request_key)
        if matching
          unless matching.order_item_id == item.id && matching.quantity == units && matching.reason == reason &&
              (!buyer_request || matching.requested_by_id == @actor.id)
            raise Invalid, 'This request changed. Reload the order and submit it again.'
          end
          next matching
        end

        requested_units = returns.counting_against_order.where(order_item_id: item.id).sum(:quantity)
        raise Invalid, 'Return quantity exceeds the unreturned units on this item.' if units > item.quantity - requested_units

        record = returns.new(order_item: item, quantity: units, reason: reason, request_key: request_key,
          requested_by_id: @actor.id)
        record.suggested_refund_fee_cents = ReturnFeePolicy.suggested_cents(site: @order.site, order: @order, item: item, record: record)
        record.save!
        record
      end
    rescue ActiveRecord::RecordInvalid => error
      raise Invalid, error.record.errors.full_messages.to_sentence
    end

    def approve!(id, refund_fee_cents: nil)
      raw = refund_fee_cents.to_s
      unless raw.empty? || (raw.match?(/\A(?:0|[1-9][0-9]{0,9})\z/) && raw.to_i <= InventoryAdjustment::MAX_QUANTITY)
        raise Invalid, 'Enter the return fee as a nonnegative whole number of cents.'
      end

      transition!(id, from: ['requested'], to: 'approved') do |record|
        fee = raw.empty? ? record.suggested_refund_fee_cents : raw.to_i
        if fee.positive?
          item = @order.items.find(record.order_item_id)
          max = ReturnRefunds.maximum_fee_cents(@order, item, record)
          if raw.empty?
            fee = [fee, max].min
          elsif fee > max
            raise Invalid, "This return can deduct a fee of up to #{max} cents."
          end
        end
        {refund_fee_cents: fee}
      end
    end
    def reject!(id) = transition!(id, from: ['requested'], to: 'rejected')
    def cancel!(id)
      transition!(id, from: %w[requested approved], to: 'canceled') do |record|
        if record.exchange_status == 'reserved'
          ReturnExchanges.new(order: @order, actor: @actor).cancel_locked!(record)
        end
        {}
      end
    end

    def receive!(id, disposition:)
      raise Invalid, 'Choose what to do with the received units.' unless DISPOSITIONS.key?(disposition)

      transition!(id, from: ['approved'], to: 'received') do |record|
        restock!(record, disposition) unless disposition == 'discarded'
        {disposition: disposition, received_at: Time.current}
      end
    end

    private

    def returns = MerchandiseReturn.where(order_id: @order.id)

    def transition!(id, from:, to:)
      @order.with_lock do
        record = returns.find(id)
        raise Invalid, 'This return has already changed. Reload the order to review its status.' unless from.include?(record.status)

        extra = block_given? ? yield(record) : {}
        record.update!(status: to, resolved_by_id: @actor.id, **extra)
      end
    rescue ActiveRecord::RecordInvalid => error
      raise Invalid, error.record.errors.full_messages.to_sentence
    rescue ActiveRecord::Deadlocked
      raise Invalid, 'Another stock transaction is in progress. Try again.'
    end

    def restock!(record, disposition)
      item = @order.items.find(record.order_item_id)
      raise Invalid, 'This order item did not use local tracked stock.' unless self.class.restockable?(@order, item)

      product = Product.where(site_id: @order.site_id, product_type: 'physical').lock.find_by(id: item.product_id)
      target = if product && item.variant_id
        product.variants.where(active: true).lock.find_by(id: item.variant_id)
      elsif product&.track_inventory? && !product.variants.where(active: true).exists?
        product
      end
      raise Invalid, 'The original product or variant is no longer tracked.' unless target

      InventoryStockStates.apply_locked!(product: product, target: target, from: nil, to: disposition, units: record.quantity,
        actor: @actor, merchandise_return: record)
    end
  end
end
