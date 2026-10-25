# frozen_string_literal: true
Rails.application.config.to_prepare do
  checkout = LightekMarketplace::CheckoutSettlement
  DymondBank::Checkout.singleton_class.prepend(checkout) unless DymondBank::Checkout.singleton_class.ancestors.include?(checkout)
  settlement = LightekMarketplace::PaidPurchaseSettlement
  DymondBank::Purchase.prepend(settlement) unless DymondBank::Purchase.ancestors.include?(settlement)
end
Rails.application.config.to_prepare do
  settlement = LightekMarketplace::InvoiceSettlement
  target = DymondBank::BillingService.singleton_class
  target.prepend(settlement) unless target.ancestors.include?(settlement)
end
