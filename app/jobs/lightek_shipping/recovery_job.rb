module LightekShipping
  class RecoveryJob < ApplicationJob
    queue_as :default
    def perform
      Shipment.where(status: "submitting").where("submitted_at < ?", 30.minutes.ago).find_each do |shipment|
        shipment.with_lock do
          next unless shipment.status == "submitting" && shipment.submitted_at < 30.minutes.ago
          shipment.update!(status: "review", error_message: "The carrier request stopped reporting. Reconcile its original transaction before buying another label.")
        end
      end
      Quote.where.not(purchase_order_id: nil).where(broker_reference: nil).includes(:purchase_order, :shipment).find_each do |quote|
        order = quote.purchase_order
        next unless order.paid_at? && %w[paid fulfilled].include?(order.status)
        LabelJob.perform_later(order.id) if !quote.shipment || quote.shipment.status == "queued"
      end
    end
  end
end
