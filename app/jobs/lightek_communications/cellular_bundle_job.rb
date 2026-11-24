# frozen_string_literal: true

module LightekCommunications
  class CellularBundleJob < ApplicationJob
    queue_as :default
    self.enqueue_after_transaction_commit = true

    def self.enqueue_paid!(order)
      return unless order&.paid_at? && order.status.in?(%w[paid fulfilled])
      return unless VoiceAddOn.where(order_id: order.id).where.not(cellular_request_key: nil).exists?

      perform_later(order.id)
    end

    def perform(order_id)
      add_on = VoiceAddOn.find_by(order_id: order_id)
      CellularBundle.new(add_on).provision! if add_on&.cellular_request_key.present?
    end
  end
end
