# frozen_string_literal: true
module LightekCommerce
  class PaidInstanceProvisioningJob < ApplicationJob
    queue_as :default
    retry_on LightekCommerce::PaidInstanceProvisioning::NotReady,
      wait: :polynomially_longer, attempts: 5

    # A PostgreSQL session advisory lock spans the external Linode allocation
    # and deployment. Locking only the order row cannot protect cloud calls
    # made after the DB transaction commits.
    def perform(order_id)
      connection = ActiveRecord::Base.connection
      lock_key = (8_155_000_000 + Integer(order_id))
      locked = connection.select_value("SELECT pg_try_advisory_lock(#{lock_key})")
      # Never acknowledge a contended job as successfully completed. Doing so
      # loses recovery if the worker holding the lock fails mid-deployment.
      unless locked == true || locked == "t"
        raise PaidInstanceProvisioning::NotReady, "Provisioning already in progress for order #{order_id}"
      end
      begin
        order = Order.find(order_id)
        return unless order.paid_at? && %w[paid fulfilled].include?(order.status)
        return unless order.items.any? { |item| item.product.product_type == "lightek_instance" }
        return if order.provisioned_at?
        PaidInstanceProvisioning.call!(order: order)
      ensure
        connection.select_value("SELECT pg_advisory_unlock(#{lock_key})")
      end
    end
  end
end
