# frozen_string_literal: true

module Gatekeeper
  module Hosting
    class WorkspacePlans
      CORE_FEATURES = %w[website design mail messaging rooms pwa].freeze
      TEAM_FEATURES = %w[people].freeze
      BUSINESS_FEATURES = %w[directory commerce accounting payments].freeze
      BASE_PRICE_CENTS = 2_500
      ADDITIONAL_SEAT_CENTS = 700
      TIERS = {
        "solo" => {
          name: "Lightek Workspace Solo", seats: 1..1,
          summary: "A CMS website, business email, documents, calendar and meetings for one person."
        }.freeze,
        "team" => {
          name: "Lightek Workspace Team", seats: 2..5,
          summary: "A CMS website and business email, plus documents, shared drives, team calendars and meetings for up to five people."
        }.freeze,
        "business" => {
          name: "Lightek Workspace Business", seats: 6..10,
          summary: "A CMS website, business email and collaboration for up to ten people, plus directory controls, CRM, invoicing and bookkeeping."
        }.freeze
      }.freeze

      def self.workspace?(product)
        subscription_plan(product).present?
      end

      def self.seats_for(product)
        tier = TIERS.keys.find { |key| product.slug == slug(key) }
        TIERS.fetch(tier).fetch(:seats) if tier && product.hosting_package && workspace?(product)
      end

      def self.target_price(seats)
        BASE_PRICE_CENTS + (seats - 1) * ADDITIONAL_SEAT_CENTS
      end

      def self.monthly_price(first_seat_price:, seats:, seat_range:)
        first_seat_price + (seats - seat_range.begin) * ADDITIONAL_SEAT_CENTS
      end

      def self.create!(source:, tier:, actor:)
        authorize!(actor)
        settings = TIERS[tier] || raise(Access::Denied, "Choose a Workspace plan")
        source_product = source.product
        site = source_product.site
        authorize_storefront!(site, actor)
        raise Access::Denied, "Choose a hosting configuration priced in USD" unless source_product.currency.to_s.casecmp?("usd")

        site.with_lock do
          existing = LightekCommerce::Product.find_by(site: site, slug: slug(tier))
          if existing
            return existing.hosting_package if workspace?(existing) && existing.hosting_package

            raise Access::Denied, "The Workspace plan slug is already in use"
          end

          entitlement = SubscriptionInfrastructureEntitlement.find_by!(subscription_plan_id: source_product.subscription_plan_id)
          raise Access::Denied, "The source plan needs a website allowance" unless entitlement.max_sites.positive?

          floor = LightekCommerce::MerchantPayouts.minimum_charge_cents(source.monthly_cost_ceiling_cents + source.minimum_margin_cents)
          price = [target_price(settings.fetch(:seats).begin), floor].max
          plan = DymondBank::SubscriptionPlan.create!(slug: subscription_slug(slug(tier), site.id), name: settings.fetch(:name),
            description: settings.fetch(:summary), price_monthly_cents: price, currency: source_product.currency, active: false)
          SubscriptionInfrastructureEntitlement.create!(entitlement.attributes.slice(
            "provisioning_profile_id", "compute_policy_id", "node_quantity", "auto_provision", "feature_entitlements"
          ).merge(subscription_plan: plan, max_sites: 1))
          product = LightekCommerce::Product.create!(site: site, name: settings.fetch(:name), slug: slug(tier),
            short_description: settings.fetch(:summary), price_cents: price, currency: source_product.currency,
            subscription_plan_id: plan.id, product_type: "lightek_instance", billing_interval: "month",
            published: false, track_inventory: false, inventory_quantity: 0,
            package_policy: policy(tier, source_product))
          HostingPackage.create!(source.attributes.slice("compute_provider_id", "gatekeeper_application_template_id",
            "region", "provider_plan", "monthly_cost_ceiling_cents", "minimum_margin_cents", "reseller_minimum_margin_cents"
          ).merge(product: product, active: false))
        end
      end

      def self.toggle!(package:, actor:)
        authorize!(actor)
        product = package.product
        authorize_storefront!(product.site, actor)
        product.with_lock do
          package.lock!
          plan = subscription_plan(product) || raise(Access::Denied, "The Workspace subscription plan is missing")
          publish = !package.active? || !product.published?
          if publish
            floor = LightekCommerce::MerchantPayouts.minimum_charge_cents(package.monthly_cost_ceiling_cents + package.minimum_margin_cents)
            raise Access::Denied, "Price must cover the cost ceiling, margin and payment fees" if product.price_cents < floor

            PackagePurchase.validate!(snapshot: package.snapshot, retail_cents: product.price_cents, actor: actor)
          end
          package.update!(active: publish)
          product.update!(published: publish)
          plan.update!(active: publish)
        end
      end

      def self.policy(tier, source_product)
        allowed = CORE_FEATURES.dup
        allowed.concat(TEAM_FEATURES) if tier != "solo"
        allowed.concat(BUSINESS_FEATURES) if tier == "business"
        storage_limit = LightekAgency::PackagePolicy.for_product(source_product).dig("limits", "max_storage_bytes")
        LightekAgency::PackagePolicy.normalize(
          "features" => LightekAgency::PackagePolicy::FEATURES.keys.to_h { |feature| [feature, { "enabled" => allowed.include?(feature) }] },
          "limits" => { "max_sites" => 1, "max_users" => TIERS.fetch(tier).fetch(:seats).end, "max_storage_bytes" => storage_limit }
        )
      end

      def self.subscription_plan(product)
        return unless product.product_type == "lightek_instance" && TIERS.keys.any? { |tier| product.slug == slug(tier) }

        DymondBank::SubscriptionPlan.find_by(id: product.subscription_plan_id,
          slug: subscription_slug(product.slug, product.site_id))
      end

      def self.subscription_slug(product_slug, site_id) = "#{product_slug}-#{site_id}"

      def self.authorize_storefront!(site, actor)
        raise Access::Denied, "Choose your platform storefront" unless LightekPwa::Policy.platform_operator(site)&.id == actor.id
      end

      def self.slug(tier) = "lightek-workspace-#{tier}"

      def self.authorize!(actor)
        raise Access::Denied, "Only the platform operator can manage Workspace plans" unless actor&.role == "super_admin"
      end
      private_class_method :slug, :subscription_slug, :authorize!, :authorize_storefront!
    end
  end
end
