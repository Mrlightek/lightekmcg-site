# frozen_string_literal: true

module LightekCommerce
  class ReturnRefunds
    def self.supported?(order)
      order.payment_namespace.present? && order.payment_reference.present? && %w[stripe stripe_invoice].include?(order.payment_provider) &&
        !order.gift_card_purchase? && !order.gift_card_redemption? && order.buyer_fee_cents.zero?
    end

    def self.available?(order, item, record)
      supported?(order) && record.order_id == order.id && item&.id == record.order_item_id && item.order_id == order.id &&
        %w[fulfilled partially_refunded].include?(order.status) && order.paid_at? &&
        !order.refunds.where(merchandise_return_id: nil, status: %w[pending succeeded]).exists?
    end

    def self.maximum_fee_cents(order, item, record)
      return 0 unless available?(order, item, record)

      # A partial return may receive an extra cent from rounding on receipt.
      # Cap the fee against the lower value before the receipt order is known.
      floor = merchandise_total(item) * record.quantity / item.quantity
      [[floor, order.total_cents - order.refunded_cents].min - 1, 0].max
    end

    def self.amount_for(order, item, record)
      return unless record.status == 'received' && available?(order, item, record)

      net = merchandise_total(item)
      return unless net.positive?

      # Receipt order fixes the allocation of fractional cents across partial returns.
      preceding = MerchandiseReturn.where(order_item_id: item.id, order_id: order.id, status: 'received')
        .where('received_at < :time OR (received_at = :time AND id < :id)', time: record.received_at, id: record.id).sum(:quantity)
      cents = net * (preceding + record.quantity) / item.quantity - net * preceding / item.quantity
      cents -= record.refund_fee_cents
      cents if cents.positive? && cents <= order.total_cents - order.refunded_cents
    end

    def self.merchandise_total(item)
      item.line_total_cents - item.purchase_snapshot.to_h['merchandise_discount_cents'].to_i
    end
    private_class_method :merchandise_total
  end
end
