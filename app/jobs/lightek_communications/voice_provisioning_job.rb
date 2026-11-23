# frozen_string_literal: true

module LightekCommunications
  class VoiceProvisioningJob < ApplicationJob
    class Busy < StandardError; end

    queue_as :default
    self.enqueue_after_transaction_commit = true
    retry_on Busy, wait: 30.seconds, attempts: 8
    retry_on VoipMs::Unavailable, wait: :polynomially_longer, attempts: 6 do |job, _error|
      VoiceAddOn.where(order_id: job.arguments.first, fulfillment_status: ["processing", "port_pending", nil])
        .update_all(fulfillment_status: "needs_attention")
    end

    def self.enqueue_paid!(order)
      return unless order.paid_at? && %w[paid fulfilled].include?(order.status)
      add_on = VoiceAddOn.find_by(order_id: order.id)
      return unless add_on&.setup_secret_slug.present? && !add_on.fulfillment_status.in?(%w[carrier_ready needs_attention])

      perform_later(order.id)
    end

    def perform(order_id)
      connection = ActiveRecord::Base.connection
      key = 8_156_000_000 + Integer(order_id)
      locked = connection.select_value("SELECT pg_try_advisory_lock(#{key})")
      raise Busy unless locked == true || locked == "t"

      begin
        add_on = VoiceAddOn.find_by(order_id: order_id)
        return unless add_on&.setup_secret_slug.present?

        if AutomaticVoiceFulfillment.call(add_on) == :waiting_for_carrier
          self.class.set(wait: 6.hours).perform_later(order_id)
        end
      ensure
        connection.select_value("SELECT pg_advisory_unlock(#{key})")
      end
    end
  end
end
