# frozen_string_literal: true

module LightekCommerce
  class OrderTimeline
    Event = Struct.new(:time, :label, :amount_cents, keyword_init: true)

    def self.for(order)
      events = [
        Event.new(time: order.created_at, label: 'Order placed'),
        Event.new(time: order.paid_at, label: 'Payment confirmed', amount_cents: order.total_cents),
        Event.new(time: order.confirmation_sent_at, label: 'Payment receipt sent'),
        Event.new(time: order.fulfilled_at, label: 'Order fulfilled'),
        Event.new(time: order.fulfillment_notification_sent_at, label: 'Fulfillment notification sent'),
        Event.new(time: order.gift_delivered_at, label: 'Gift card delivered'),
        Event.new(time: order.canceled_at, label: 'Order canceled')
      ]
      order.refunds.sort_by(&:id).each do |refund|
        events << Event.new(time: refund.created_at, label: 'Refund requested', amount_cents: refund.amount_cents)
        label = {'succeeded' => 'Refund recorded as successful', 'failed' => 'Refund recorded as failed'}[refund.status]
        events << Event.new(time: refund.updated_at, label: label, amount_cents: refund.amount_cents) if label
      end
      events.select(&:time).each_with_index.sort_by { |event, index| [event.time, index] }.map(&:first)
    end
  end
end
