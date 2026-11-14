module LightekReservations
  module Federation
    module Catalog
      module_function
      def approved
        Resource.available.where(kind: 'server', source_resource_id: nil)
          .where(site_id: DymondSite::Site.where(tenant: User.where(role: 'super_admin')).select(:id)).joins(:product).where(lightek_commerce_products: {published: true}).where.not(product_id: HostingPackage.where(active: false).select(:product_id)).includes(:product)
      end
      def serialize(resource)
        {'id'=>resource.id, 'name'=>resource.name, 'description'=>resource.description,
          'price_cents'=>resource.price_cents, 'minimum_price_cents'=>resource.source_resource_id ? resource.minimum_price_cents : LightekCommerce::MerchantPayouts.minimum_charge_cents(resource.price_cents), 'cost_floor_cents'=>resource.source_resource_id ? resource.cost_floor_cents : resource.price_cents,
          'billing_interval'=>resource.billing_interval, 'template_key'=>resource.template_key,
          'accommodations'=>resource.accommodations, 'published'=>resource.published?, 'source_id'=>resource.source_resource&.product&.hosting_package ? "hosting:#{resource.source_resource.product.hosting_package.id}" : resource.source_resource_id,
          'package_policy'=>LightekAgency::PackagePolicy.normalize(resource.product.respond_to?(:package_policy) ? resource.product.package_policy : {}), 'timezone'=>resource.timezone, 'notice_minutes'=>resource.notice_minutes}
      end
      def offers(peer)
        Resource.where(site_id: peer.site_id, kind: 'server').includes(:product)
      end
      def save!(peer:, attributes:)
        attributes = attributes.stringify_keys
        source_key = attributes.fetch('source_id').to_s
        source = source_key.start_with?('hosting:') ? LightekAgency::HostingCatalog.materialize!(source_key) : approved.find(source_key)
        raise ArgumentError, 'Choose a priced offer above the protected platform floor' unless attributes.fetch('price_cents').to_s.match?(/\A[1-9]\d*\z/)
        price = Integer(attributes.fetch('price_cents'))
        raise ArgumentError, 'Selling price is below the protected platform floor' if price < LightekCommerce::MerchantPayouts.minimum_charge_cents(source.price_cents)
        # The base floor is reserved centrally. Merchants never supply compute,
        # subscription IDs, fee rules, payout destinations, or ownership IDs.
        source.with_lock do
          resource = attributes['id'].present? ? offers(peer).find(attributes['id']) : Resource.new(site: peer.site)
          resource.with_lock do
            product = resource.product || LightekCommerce::Product.new(site: peer.site, slug: "resort-#{SecureRandom.hex(8)}", inventory_quantity: 100_000)
            product.assign_attributes(name: attributes.fetch('name'), product_type: 'lightek_instance',
              price_cents: price, subscription_plan_id: source.product.subscription_plan_id, published: ActiveModel::Type::Boolean.new.cast(attributes['published']))
            policy = LightekAgency::PackagePolicy.restrict!(upstream: LightekAgency::PackagePolicy.for_product(source.product), requested: attributes.fetch('package_policy', {}))
            product.package_policy = policy
            if (hosting = source.product.hosting_package)
              product.source_hosting_package = hosting
              product.billing_interval = source.product.billing_interval
            end
            product.save!
            resource.assign_attributes(name: attributes.fetch('name'), description: attributes['description'], kind: 'server',
              source_resource: source, product: product, template_key: attributes['template_key'].presence,
              accommodations: source.accommodations, compute: source.compute, cost_floor_cents: source.price_cents,
              billing_interval: source.billing_interval, timezone: source.timezone, notice_minutes: source.notice_minutes,
              published: product.published?)
            resource.save!
            resource
          end
        end
      end
      def create_intent!(peer:, attributes:)
        attributes = attributes.stringify_keys
        peer.with_lock do
          existing = peer.intents.find_by(checkout_key: attributes.fetch('checkout_key'))
          if existing
            raise ArgumentError, 'Checkout identity mismatch' unless existing.remote_subject == attributes.fetch('subject') && existing.resource_id.to_s == attributes.fetch('offer_id').to_s
            raise ArgumentError, 'Checkout has expired' unless existing.reservation_id || existing.expires_at > Time.current
            return existing
          end
          offer = offers(peer).available.find(attributes.fetch('offer_id'))
          start = Availability.parse(attributes.fetch('starts_at'), offer)
          finish = offer.billing_interval == 'annual' ? start + 1.year : start + 1.month
          Availability.check!(resource: offer, starts_at: start, ends_at: finish)
          peer.intents.create!(resource: offer, token: SecureRandom.hex(32), checkout_key: attributes.fetch('checkout_key'),
            remote_subject: attributes.fetch('subject'), starts_at: start, expires_at: 30.minutes.from_now, price_cents: offer.price_cents)
        end
      end
      def book!(intent:, customer:)
        intent.with_lock do
          raise ArgumentError, 'This checkout belongs to another account' if intent.customer_id && intent.customer_id != customer.id
          return intent.reservation if intent.reservation
          raise ArgumentError, 'Checkout expired or reseller connection disabled' unless intent.expires_at > Time.current && intent.peer.active?
          intent.resource.with_lock do
            intent.resource.product.lock!
            raise ArgumentError, 'Offer price changed; request a fresh checkout' unless intent.resource.price_cents == intent.price_cents
            reservation = Booking.reserve!(customer: customer, resource: intent.resource, starts_at: intent.starts_at.iso8601,
              checkout_key: intent.checkout_key, notes: 'Booked through a Lightek server resort partner')
            intent.update!(customer: customer, reservation: reservation)
            reservation
          end
        end
      end
    end
  end
end
