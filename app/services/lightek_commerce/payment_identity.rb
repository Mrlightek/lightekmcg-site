# frozen_string_literal: true
require 'digest'
module LightekCommerce
  module PaymentIdentity
    module_function
    def namespace(site) = Digest::SHA256.hexdigest(site.host.to_s.downcase).first(20)
    # Existing orders retain their original Stripe idempotency keys for recovery.
    # New orders include the site identity because isolated servers can all have
    # order #1 while charging the same Lightek platform Stripe account.
    def key(order, suffix)
      prefix = order.payment_namespace.present? ? "lightek-commerce-#{order.payment_namespace}" : 'lightek-commerce'
      "#{prefix}-order-#{order.id}-#{suffix}"
    end
    def metadata(order)
      {lightek_commerce_order_id: order.id.to_s, lightek_site_id: order.site_id.to_s}.tap do |data|
        data[:lightek_host_key] = order.payment_namespace if order.payment_namespace.present?
      end
    end
  end
end
