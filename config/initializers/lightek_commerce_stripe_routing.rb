# frozen_string_literal: true

# Reuse the verified Stripe event from Dymond Bank's existing webhook.
module LightekCommerceStripeRouting
  def process!(event)
    if commerce_checkout?(event)
      LightekCommerce::StripeEvents.process!(event)
    else
      super
    end
  end

  private

  def commerce_checkout?(event)
    types = %w[checkout.session.completed checkout.session.async_payment_succeeded checkout.session.expired]
    return false unless types.include?(event.type)

    event.data.object.metadata.to_h["lightek_commerce_order_id"].to_s != ""
  end
end

Rails.application.config.to_prepare do
  klass = DymondBank::StripeWebhookService.singleton_class
  klass.prepend(LightekCommerceStripeRouting) unless klass.ancestors.include?(LightekCommerceStripeRouting)
end
