# frozen_string_literal: true
module LightekCommerce
  class InstanceReadyMailer < ApplicationMailer
    def ready(order_id)
      @order = Order.find(order_id)
      raise ArgumentError, "Installation is not ready" unless @order.provisioned_at?
      @hostname = "client-#{@order.id}.#{ENV.fetch('LIGHTEK_AUTO_CLIENT_BASE_DOMAIN', 'lightekmcg.com')}"
      mail(to: @order.customer_email, subject: "Your Lightek installation is ready")
    end
  end
end
