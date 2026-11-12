module LightekCommerce
  class SubscriptionCancellation
    def self.schedule!(subscription:)
      if subscription.order.payment_provider == "network"
        NetworkCheckout.action!(order: subscription.order, action: "cancel-subscription")
        return subscription.reload
      end
      Stripe.api_key = DymondBank::StripeCredentials.secret_key
      remote = Stripe::Subscription.update(subscription.processor_reference, {cancel_at_period_end: true},
        {idempotency_key: "commerce-cancel-#{subscription.processor_reference}"})
      subscription.with_lock { SubscriptionEvents.apply!(subscription: subscription, data: remote.to_h.deep_stringify_keys) }
      subscription
    end
  end
end
