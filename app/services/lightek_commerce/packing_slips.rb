# frozen_string_literal: true

module LightekCommerce
  class PackingSlips
    class Invalid < StandardError; end

    MAX_ORDERS = 50
    Slip = Struct.new(:order, :items, :recipient, keyword_init: true)

    def self.eligible?(order)
      order.paid_at? && %w[paid fulfilled partially_refunded].include?(order.status) &&
        order.items.any?(&:physical_for_fulfillment?)
    end

    def self.for(site:, order_ids:)
      ids = Array(order_ids).map(&:to_s).uniq
      unless ids.size.between?(1, MAX_ORDERS) && ids.all? { |id| id.match?(/\A[1-9][0-9]{0,17}\z/) }
        raise Invalid, "Select between 1 and #{MAX_ORDERS} paid physical orders."
      end

      orders = Order.receipt_eligible.where(site: site).where.not(status: 'refunded')
        .includes(:shipping_quote, items: :product).find(ids)
      slips = orders.map do |order|
        items = order.items.select(&:physical_for_fulfillment?)
        raise ActiveRecord::RecordNotFound if items.empty?

        recipient = order.shipping_quote&.shipment_payload.to_h.fetch('recipients', []).first
        Slip.new(order: order, items: items, recipient: recipient)
      end
      slips
    end
  end
end
