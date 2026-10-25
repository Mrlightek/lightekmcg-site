# frozen_string_literal: true
module LightekMarketplace
  module AccessLifecycle
    # Revoke only grants owned by the canceled purchase. Pre-existing manual
    # entitlements remain untouched; another active purchase preserves access.
    def cancel!(...)
      with_lock do
        result = super
        DymondBank::Purchase.where(subscription_id: id).find_each do |purchase|
          config = purchase.offer.meta.to_h["lightek_marketplace"]
          next unless config && [88, 89].include?(config["version"]) && config["delivery"] == "access"
          source = "marketplace-purchase-#{purchase.id}"
          grant = UserFeatureEntitlement.find_by(user_id: purchase.customer_id, source: source,
            feature_slug: config["feature_key"])
          next unless grant
          grant.with_lock do
            alternative = DymondBank::Purchase.where(customer_type: purchase.customer_type,
              customer_id: purchase.customer_id, status: "provisioned").where.not(id: purchase.id).includes(:offer, :subscription).detect do |other|
              c = other.offer.meta.to_h["lightek_marketplace"]
              c && [88, 89].include?(c["version"]) && c["delivery"] == "access" && c["feature_key"] == config["feature_key"] &&
                (other.subscription.nil? || (other.subscription.active? && !other.subscription.trial_expired?))
            end
            if alternative
              grant.update!(source: "marketplace-purchase-#{alternative.id}")
            else
              grant.update!(active: false, revoked_at: Time.current)
            end
          end
        end
        result
      end
    end
  end
end
