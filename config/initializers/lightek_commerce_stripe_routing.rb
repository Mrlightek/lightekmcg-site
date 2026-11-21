# frozen_string_literal: true

# Reuse the verified Stripe event from Dymond Bank's existing webhook.
module LightekCommerceStripeRouting
  def process!(event)
    if DymondBank::BroadcastAdvertising::Funding.checkout_event?(event)
      DymondBank::BroadcastAdvertising::Funding.process!(event)
    elsif %w[charge.refund.updated refund.updated charge.refunded charge.dispute.created charge.dispute.closed].include?(event.type)
      # These events can concern both Bank/Susu and Commerce records. Preserve
      # Bank handling and let Commerce reconcile only its own recorded IDs.
      result = super
      commerce_result = LightekCommerce::StripeEvents.process!(event)
      DymondBank::BroadcastAdvertising::Funding.process!(event)
      result || commerce_result
    elsif commerce_checkout?(event)
      LightekCommerce::StripeEvents.process!(event)
    else
      super
    end
  end

  private

  def commerce_checkout?(event)
    if LightekCommerce::SubscriptionEvents::TYPES.include?(event.type)
      return !LightekCommerce::SubscriptionEvents.metadata(event)["lightek_commerce_order_id"].to_s.empty? ||
        LightekCommerce::Subscription.exists?(processor_reference: LightekCommerce::SubscriptionEvents.reference(event))
    end
    types = %w[checkout.session.completed checkout.session.async_payment_succeeded checkout.session.expired]
    return false unless types.include?(event.type)

    !event.data.object.metadata.to_h.transform_keys(&:to_s)["lightek_commerce_order_id"].to_s.empty?
  end
end

Rails.application.config.to_prepare do
  klass = DymondBank::StripeWebhookService.singleton_class
  klass.prepend(LightekCommerceStripeRouting) unless klass.ancestors.include?(LightekCommerceStripeRouting)
end
