module Gatekeeper
  module Hosting
    class RetailPricing
      def self.update!(package:, actor:, price_cents:, minimum_margin_cents: nil)
        raise Access::Denied, 'Only the platform operator can set hosting prices' unless actor&.role == 'super_admin'
        price = Integer(price_cents.to_s, 10)
        raise Access::Denied, 'Enter a positive whole-cent monthly price' unless price.positive?
        margin = Integer(minimum_margin_cents.to_s, 10) unless minimum_margin_cents.nil?
        raise Access::Denied, 'Enter a positive whole-cent minimum margin' if margin && !margin.positive?
        package.product.with_lock do
          package.lock!
          package.minimum_margin_cents = margin if margin
          floor = package.monthly_cost_ceiling_cents + package.minimum_margin_cents
          if price < LightekCommerce::MerchantPayouts.minimum_charge_cents(floor)
            raise Access::Denied, 'Price must cover the vendor cost ceiling, margin and payment fees'
          end
          PackagePurchase.validate!(snapshot: package.snapshot, retail_cents: price, actor: actor)
          package.product.update!(price_cents: price)
          package.save!
        end
        # Existing order line prices, processor subscriptions and hosting
        # snapshots remain unchanged. Only future checkouts use this price.
        package
      rescue ArgumentError, TypeError
        raise Access::Denied, 'Enter positive whole-cent values for price and minimum margin'
      end
    end
  end
end
