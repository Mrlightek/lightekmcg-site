# frozen_string_literal: true
module LightekCommerce
  class Fulfillment
    class Invalid < StandardError; end
    def self.complete!(order:, reference:, note: nil)
      order.with_lock do
        return order if order.status == "fulfilled"
        raise Invalid, "Only verified paid orders may be fulfilled" unless order.status == "paid"
        order.update!(status: "fulfilled", fulfilled_at: Time.current,
          fulfillment_reference: reference.to_s.strip.presence,
          fulfillment_note: note.to_s.strip.presence)
      end
      FulfillmentNotificationJob.perform_later(order.id)
      order
    end
  end
end
