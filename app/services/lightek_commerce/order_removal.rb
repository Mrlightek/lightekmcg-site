# frozen_string_literal: true
module LightekCommerce
  class OrderRemoval
    class Invalid < StandardError; end

    # Keep the canceled record for delayed webhooks and network receipts, while
    # removing it from the merchant's orders list. Never delete payment history.
    def self.call(order)
      order.with_lock do
        raise Invalid, "Only unpaid orders without an installation can be deleted." unless order.removable?
        return order if order.deleted_at?

        if order.status == "pending_payment"
          if order.payment_provider == "network"
            NetworkCheckout.synchronize!(order)
            raise Invalid, "Network checkout must expire or be canceled upstream before deletion." unless order.reload.status == "canceled"
          elsif order.payment_reference.present?
            expire_checkout!(order)
          end
          OrderPlacement.cancel!(order) if order.status == "pending_payment"
        end

        raise Invalid, "This order has payment or installation activity and cannot be deleted." unless order.removable?
        order.update!(deleted_at: Time.current)
      end
      order
    rescue ::Stripe::StripeError
      raise Invalid, "Checkout could not be expired. The order was kept; try again after payment reconciliation."
    rescue LightekReservations::Federation::Client::Unavailable, StripeCheckout::Unavailable
      raise Invalid, "Network checkout could not be verified. The order was kept; try again later."
    end

    def self.expire_checkout!(order)
      raise Invalid, "This payment provider must confirm cancellation before deletion." unless order.payment_provider == "stripe"
      key = DymondBank::StripeCredentials.secret_key
      raise Invalid, "Stripe must be configured to safely cancel this checkout." if key.blank?
      options = {api_key: key}
      session = Stripe::Checkout::Session.retrieve(order.payment_reference, options)
      metadata = session.metadata.to_h.stringify_keys
      raise Invalid, "Checkout does not match this order." unless session.id == order.payment_reference &&
        metadata["lightek_commerce_order_id"].to_s == order.id.to_s && metadata["lightek_site_id"].to_s == order.site_id.to_s
      if session.payment_status == "paid" || session.status == "complete"
        raise Invalid, "Checkout has completed or is settling. Reconcile payment before deleting this order."
      end
      session = Stripe::Checkout::Session.expire(session.id, {}, options) if session.status == "open"
      raise Invalid, "Checkout cancellation was not confirmed. The order was kept." unless session.status == "expired" && session.payment_status != "paid"
    end
    private_class_method :expire_checkout!
  end
end
