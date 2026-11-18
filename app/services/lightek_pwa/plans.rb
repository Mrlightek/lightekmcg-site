module LightekPwa
  class Plans
    class Unavailable < StandardError; end
    CATALOG = {
      'community' => {name: 'Community', features: ['Free shared hosting for your account and originals', 'Social discovery, communities and messages', 'Your public profile']},
      'personal' => {name: 'Personal', features: ['Dedicated Lightek hosting', 'Your account and originals move to your own instance', 'Discovery through the Lightek network']},
      'business' => {name: 'Business / Agency', features: ['Dedicated business hosting', 'White label branding and client management', 'Resell client server packages at your prices']}
    }.freeze
    def self.configuration(site) = site.manifest.to_h.fetch('pwa_commerce', {})
    def self.current(user, site)
      return nil unless user && site
      Purchase.where(user: user, site: site).includes(order: :commerce_subscription).order(id: :desc).detect(&:entitled?)
    end
    def self.enabled?(site) = configuration(site)['enabled'] == true && LaunchReadiness.paid_ready?(site)
    def self.product(site, key)
      id = configuration(site).fetch('products', {})[key]
      return unless id && %w[personal business].include?(key)
      LightekCommerce::Product.find_by(id: id, site: site, published: true, product_type: 'lightek_instance', billing_interval: 'month', currency: 'usd')
    end
    def self.payload(user:, site:)
      purchase = current(user, site)
      pending = user && Purchase.where(user: user, site: site).order(id: :desc).detect { |p| p.order.status == 'pending_payment' || (p.order.paid_at? && %w[paid fulfilled].include?(p.order.status) && !p.order.provisioned_at?) }
      record = purchase || pending
      {current_plan: purchase&.plan_key || 'community', enabled: enabled?(site),
        cancel_at_period_end: purchase&.order&.commerce_subscription&.cancel_at_period_end || false,
        current_period_end: purchase&.order&.commerce_subscription&.current_period_end,
        backend: (user && defined?(MemberBackend) && MemberBackend.find_by(user: user, site: site))&.summary,
        installation: record && LightekCommerce::Installations.summary(record.order),
        installation_path: record && "/my/installations/#{record.order_id}",
        setup_note: 'Free accounts use shared hosting. Paid membership includes dedicated hosting: your account and its originals move to your own instance after verified payment, installation and migration. Other shared customers stay on shared hosting. Cancel renewal at any time; access continues through the paid period. Storage and transfer limits follow your selected server package.',
        plans: CATALOG.map do |key, plan|
          item = product(site, key)
          plan.merge(key: key, price_cents: key == 'community' ? 0 : item&.price_cents, available: key == 'community' || (enabled?(site) && item.present?))
        end}
    end
    def self.install!(site:, actor:, personal_product_id:, business_product_id: nil)
      Policy.authorize_platform!(user: actor, site: site)
      raise Unavailable, 'Complete the launch configuration, including a verified separate member host, before opening paid membership' unless LaunchReadiness.paid_ready?(site)
      site.with_lock do
        mapping = {'personal' => personal_product_id, 'business' => business_product_id}.reject { |_, id| id.blank? }
        raise Unavailable, 'Choose a personal server package' if mapping['personal'].blank?
        mapping.each do |tier, id|
          item = LightekCommerce::Product.where(site: site, published: true, product_type: 'lightek_instance', billing_interval: 'month', currency: 'usd').find(id)
          if tier == 'business' && !LightekAgency::PackagePolicy.for_product(item).dig('features', 'agency', 'enabled')
            raise Unavailable, 'The Business package must include agency features'
          end
          package = item.hosting_package
          raise Unavailable, 'Select an active managed hosting package with a subscription plan' unless package&.active? && package.gatekeeper_application_template.kind == 'native_rails' && item.subscription_plan_id
          floor = package.monthly_cost_ceiling_cents + package.minimum_margin_cents
          raise Unavailable, 'Membership price must cover infrastructure, margin and payment fees' if item.price_cents < LightekCommerce::MerchantPayouts.minimum_charge_cents(floor)
        end
        site.update!(manifest: site.manifest.to_h.merge('pwa_commerce' => {'enabled' => true, 'products' => mapping.transform_values(&:to_i)}))
      end
    end
    def self.checkout!(user:, site:, key:, success_url:, cancel_url:)
      raise Unavailable, 'Paid membership is not open yet' unless enabled?(site)
      item = product(site, key) or raise Unavailable, 'Choose an available paid plan'
      if key == 'business' && !user.role.in?(%w[client member white_label super_admin])
        raise Unavailable, 'Business membership requires a member or agency account'
      end
      package = item.hosting_package
      raise Unavailable, 'Choose an active native hosting package for a migratable PWA backend' unless package&.active? && package.gatekeeper_application_template.kind == 'native_rails'
      floor = package.monthly_cost_ceiling_cents + package.minimum_margin_cents
      raise Unavailable, 'This package needs a price review before checkout' if item.price_cents < LightekCommerce::MerchantPayouts.minimum_charge_cents(floor)
      purchase = nil
      user.with_lock do
        backend = defined?(MemberBackend) && MemberBackend.find_by(site: site, user: user)
        raise Unavailable, 'Wait for your shared backend to finish setup before upgrading' if backend && backend.status != 'shared_ready'
        raise Unavailable, 'You already have a paid instance. Manage its subscription before buying another membership.' if current(user, site)
        purchase = Purchase.where(user: user, site: site).joins(:order).where(lightek_commerce_orders: {status: 'pending_payment'}).order(id: :desc).first
        raise Unavailable, 'Finish or wait for your existing checkout to expire before selecting another plan' if purchase && purchase.plan_key != key
        unless purchase
          order = LightekCommerce::OrderPlacement.call(site: site, customer_email: user.email_address, quantities: {item.id.to_s => 1})
          order.update!(hosting_owner: user)
          purchase = Purchase.create!(user: user, site: site, order: order, plan_key: key)
        end
      end
      LightekCommerce::StripeCheckout.start!(order: purchase.order, success_url: success_url, cancel_url: cancel_url)
    end
  end
end
