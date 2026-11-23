module Gatekeeper
  module Hosting
    class RetailPricing
      def self.update!(package:, actor:, price_cents:, minimum_margin_cents: nil, wholesale_price_cents: :unchanged, reseller_minimum_margin_cents: nil)
        raise Access::Denied, 'Only the platform operator can set hosting prices' unless actor&.role == 'super_admin'
        price = Integer(price_cents.to_s, 10)
        raise Access::Denied, 'Enter a positive whole-cent monthly price' unless price.positive?
        margin = Integer(minimum_margin_cents.to_s, 10) unless minimum_margin_cents.nil?
        raise Access::Denied, 'Enter a positive whole-cent minimum margin' if margin && !margin.positive?
        wholesale = wholesale_price_cents == :unchanged ? :unchanged : (wholesale_price_cents.to_s.strip.empty? ? nil : Integer(wholesale_price_cents.to_s, 10))
        reseller_margin = Integer(reseller_minimum_margin_cents.to_s, 10) unless reseller_minimum_margin_cents.nil?
        raise Access::Denied, 'Enter a positive whole-cent agency wholesale price' if wholesale.is_a?(Integer) && !wholesale.positive?
        raise Access::Denied, 'Enter a nonnegative whole-cent agency margin' if reseller_margin && reseller_margin.negative?
        package.product.with_lock do
          package.lock!
          package.minimum_margin_cents = margin if margin
          package.wholesale_price_cents = wholesale unless wholesale == :unchanged
          package.reseller_minimum_margin_cents = reseller_margin unless reseller_margin.nil?
          floor = package.monthly_cost_ceiling_cents + package.minimum_margin_cents
          if price < LightekCommerce::MerchantPayouts.minimum_charge_cents(floor)
            raise Access::Denied, 'Price must cover the vendor cost ceiling, margin and payment fees'
          end
          PackagePurchase.validate!(snapshot: package.snapshot, retail_cents: price, actor: actor)
          if package.wholesale_price_cents && package.wholesale_price_cents < LightekCommerce::MerchantPayouts.minimum_charge_cents(floor)
            raise Access::Denied, 'Agency wholesale price must cover vendor cost, your minimum margin and payment fees'
          end
          workspace_plan = WorkspacePlans.subscription_plan(package.product)
          if workspace_plan && price > WorkspacePlans::MAX_CHECKOUT_CENTS
            raise Access::Denied, "Price exceeds the Workspace checkout limit"
          end
          package.product.assign_attributes(price_cents: price)
          package.save!
          package.product.save!
          workspace_plan&.update!(price_monthly_cents: price)
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
