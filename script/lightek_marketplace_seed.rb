# Creates merchandising only; never creates offers, prices, orders or subscriptions.
eligible_plan_ids = SubscriptionInfrastructureEntitlement.pluck(:subscription_plan_id)
DymondBank::Offer.where(active: true, subscription_plan_id: eligible_plan_ids).find_each do |offer|
  DymondCatalog::MarketplaceListing.find_or_create_by!(offer_id: offer.id) do |listing|
    listing.title = offer.name
    listing.summary = "Your digital foundation, connected to the Lightek ecosystem. Review this plan’s pricing and enrollment terms."
    listing.category = "cloud"
    listing.published = false
  end
end
puts "MARKETPLACE_CATALOG_READY listings=#{DymondCatalog::MarketplaceListing.count} published=#{DymondCatalog::MarketplaceListing.storefront.count}"
puts "Review eligible drafts in Dashboard Marketplace before publishing."
puts "No eligible hosting offers matched the configured plan entitlements." if DymondCatalog::MarketplaceListing.count.zero?
