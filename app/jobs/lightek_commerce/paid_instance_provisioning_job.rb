# frozen_string_literal: true
module LightekCommerce
  class PaidInstanceProvisioningJob < ApplicationJob
    queue_as :default
    retry_on LightekCommerce::PaidInstanceProvisioning::NotReady,
      wait: :polynomially_longer, attempts: 5

    def perform(order_id)
      order = Order.find(order_id)
      return unless order.paid_at? && %w[paid fulfilled].include?(order.status)
      return unless order.items.any? { |item| item.product.product_type == "lightek_instance" }
      return if order.provisioned_at?
      PaidInstanceProvisioning.call!(order: order)
    end
  end
end
