module LightekCommerce
  class NetworkSyncJob < ApplicationJob
    queue_as :default
    def perform
      return if ENV["LIGHTEK_DEPLOYED_SITE_HOST"].blank?
      active = Subscription.where(status: %w[active trialing past_due]).select(:order_id)
      candidates = Order.where(status: "pending_payment").or(Order.where("paid_at > ?", 7.days.ago)).or(Order.where(id: active))
      Order.where(payment_provider: "network", network_invoice_reference: nil).merge(candidates)
        .find_each(batch_size: 100) do |order|
        begin
          NetworkCheckout.synchronize!(order)
        rescue StandardError => error
          Rails.logger.warn("[Network commerce] order=#{order.id} sync=#{error.class}")
        end
      end
    end
  end
end
