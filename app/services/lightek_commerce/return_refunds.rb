# frozen_string_literal: true

module LightekCommerce
  class ReturnRefunds
    def self.supported?(order)
      order.payment_namespace.present? && order.payment_reference.present? && %w[stripe stripe_invoice].include?(order.payment_provider) &&
        !order.gift_card_purchase? && !order.gift_card_redemption? && order.buyer_fee_cents.zero?
    end

    def self.amount_for(order, item, record)
      return unless supported?(order) && record.status == 'received' && record.order_id == order.id &&
        item&.id == record.order_item_id && item.order_id == order.id
      return unless %w[fulfilled partially_refunded].include?(order.status) && order.paid_at?
      return if order.refunds.where(merchandise_return_id: nil, status: %w[pending succeeded]).exists?

      discount = item.purchase_snapshot.to_h['merchandise_discount_cents'].to_i
      net = item.line_total_cents - discount
      return unless net.positive?

      # Receipt order fixes the allocation of fractional cents across partial returns.
      preceding = MerchandiseReturn.where(order_item_id: item.id, order_id: order.id, status: 'received')
        .where('received_at < :time OR (received_at = :time AND id < :id)', time: record.received_at, id: record.id).sum(:quantity)
      cents = net * (preceding + record.quantity) / item.quantity - net * preceding / item.quantity
      cents if cents.positive? && cents <= order.total_cents - order.refunded_cents
    end
  end
end
