module Gatekeeper
  module Hosting
    class RetailPricing
      def self.update!(package:, actor:, price_cents:)
        raise Access::Denied, 'Only the platform operator can set hosting prices' unless actor&.role == 'super_admin'
        price = Integer(price_cents.to_s, 10)
        raise Access::Denied, 'Enter a positive whole-cent monthly price' unless price.positive?
        package.product.with_lock do
          floor = package.monthly_cost_ceiling_cents + package.minimum_margin_cents
          if price < LightekCommerce::MerchantPayouts.minimum_charge_cents(floor)
            raise Access::Denied, 'Price must cover the vendor cost ceiling, margin and payment fees'
          end
          PackagePurchase.validate!(snapshot: package.snapshot, retail_cents: price, actor: actor)
          package.product.update!(price_cents: price)
        end
        # Existing order line prices, processor subscriptions and hosting
        # snapshots remain unchanged. Only future checkouts use this price.
        package
      rescue ArgumentError, TypeError
        raise Access::Denied, 'Enter a positive whole-cent monthly price'
      end
    end
  end
end
