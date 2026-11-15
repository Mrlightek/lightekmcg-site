module LightekSales
  class Quotes
    def initialize(actor:, site:)
      @workspace = Workspace.new(actor: actor, site: site)
      @actor, @site = actor, @workspace.site
    end
    def draft!(opportunity_id:, values:, quantities:, previous_id: nil, portal_host: nil)
      @site.with_lock do
        @workspace.revalidate!
        opportunity = @workspace.find('opportunity', opportunity_id)
        raise ArgumentError, 'Catalog checkout currently supports USD deals.' unless opportunity.currency == 'USD'
        previous = Quote.where(site: @site, opportunity: opportunity).find(previous_id) if previous_id
        if previous && Quote.where(site: @site, series_key: previous.series_key, status: 'accepted').exists?
          raise ArgumentError, 'This quote series already has an accepted order.'
        end
        lines = self.class.catalog_lines(@site, quantities)
        attrs = values.to_h.stringify_keys.slice('title', 'customer_email', 'terms', 'expires_on')
        Quote.create!(attrs.merge(portal_host: (portal_host || previous&.portal_host || @site.host).to_s.downcase, site: @site, opportunity: opportunity, created_by: @actor, lines: lines, total_cents: lines.sum { |line| line['quantity'] * line['unit_price_cents'] },
          series_key: previous&.series_key || SecureRandom.uuid, revision: previous ? Quote.where(site: @site, series_key: previous.series_key).maximum(:revision) + 1 : 1))
      end
    end
    def issue!(id:, version:)
      @site.with_lock do
        @workspace.revalidate!
        quote = Quote.where(site: @site).find(id)
        check_version!(quote, version)
        raise ArgumentError, 'Only a draft can be issued.' unless quote.status == 'draft'
        raise ArgumentError, 'Set an expiry today or later.' if quote.expires_on < Date.current
        raise ArgumentError, 'This series already has an accepted order.' if Quote.where(site: @site, series_key: quote.series_key, status: 'accepted').exists?
        raise ArgumentError, 'Issue the latest revision in this series.' if Quote.where(site: @site, series_key: quote.series_key).maximum(:revision) > quote.revision
        self.class.verify_catalog!(quote)
        Quote.where(site: @site, series_key: quote.series_key, status: 'issued').find_each { |old| old.update!(status: 'superseded') }
        quote.update!(status: 'issued', issued_at: Time.current)
        Activity.create!(site: @site, actor: @actor, record: quote.opportunity, kind: 'note', body: "Issued quote ##{quote.id}, revision #{quote.revision}. Awaiting customer acceptance.")
        Rails.logger.info({event: 'lightek.sales.quote_issued', quote_id: quote.id, revision: quote.revision, site_id: @site.id, actor_id: @actor.id}.to_json)
        quote
      end
    end
    def self.accept!(quote:, name:, reference:, actor: nil)
      Workspace.new(actor: actor.reload, site: quote.site) if actor
      quote.site.with_lock do
        quote.reload
        return quote if quote.status == 'accepted' && quote.order_id
        raise ArgumentError, 'This quote is no longer available for acceptance.' unless quote.status == 'issued' && quote.expires_on >= Date.current
        raise ArgumentError, 'Record the customer name and approval reference.' if name.to_s.strip.blank? || name.to_s.length > 160 || reference.to_s.strip.blank? || reference.to_s.length > 300
        raise ArgumentError, 'Reopen the lost deal before accepting a quote.' if quote.opportunity.stage == 'closed_lost'
        verify_catalog!(quote)
        order = LightekCommerce::OrderPlacement.call(site: quote.site, customer_email: quote.customer_email,
          quantities: quote.lines.to_h { |line| [line['product_id'].to_s, line['quantity']] }, growth_visit: quote.opportunity.growth_attribution)
        raise ArgumentError, 'Catalog prices changed. Issue a revised quote.' unless order.total_cents == quote.total_cents &&
          order.items.all? { |item| quote.lines.any? { |line| line['product_id'] == item.product_id && line['quantity'] == item.quantity && line['unit_price_cents'] == item.unit_price_cents } }
        quote.update!(accepted_by: actor, acceptance_channel: actor ? 'staff' : 'customer_portal', status: 'accepted', accepted_at: Time.current, accepted_name: name.to_s.strip, acceptance_reference: reference.to_s.strip, order: order)
        quote.opportunity.update!(stage: 'closed_won', amount_cents: quote.total_cents)
        Activity.create!(site: quote.site, actor: actor || quote.site.tenant, record: quote.opportunity, kind: 'note', body: "#{actor ? 'Staff recorded customer approval' : 'Customer portal acknowledgment'} by #{name.to_s.strip} for quote ##{quote.id}; pending order ##{order.id}. Payment is not yet confirmed.")
        Rails.logger.info({event: 'lightek.sales.quote_accepted', quote_id: quote.id, order_id: order.id, site_id: quote.site_id, actor_id: actor&.id, channel: quote.acceptance_channel}.to_json)
        quote
      end
    end
    def self.catalog_lines(site, quantities)
      raise ArgumentError, 'Choose 1–50 catalog items.' unless quantities.respond_to?(:to_h) && quantities.size.in?(1..50)
      quantities = quantities.to_h.stringify_keys
      raise ArgumentError, 'Choose product IDs and quantities from 1 to 100.' unless quantities.all? { |id, qty| id.match?(/\A[1-9]\d*\z/) && qty.to_s.match?(/\A[1-9]\d*\z/) && qty.to_i <= 100 }
      products = LightekCommerce::Product.where(site: site, id: quantities.keys).order(:id).lock.to_a
      raise ArgumentError, 'Choose published service, digital or managed-installation products from this website.' unless products.size == quantities.size && products.all? { |p| p.published? && p.currency == 'usd' && p.product_type.in?(%w[service digital lightek_instance]) && !p.variants.where(active: true).exists? }
      lines = products.map { |p| {'product_id' => p.id, 'name' => p.name, 'quantity' => quantities.fetch(p.id.to_s).to_i, 'unit_price_cents' => p.price_cents, 'billing_interval' => p.billing_interval, 'product_type' => p.product_type, 'subscription_plan_id' => p.subscription_plan_id, 'hosting' => p.effective_hosting_package&.snapshot, 'managed_policy' => (LightekAgency::PackagePolicy.for_product(p) if p.product_type == 'lightek_instance' && p.has_attribute?(:package_policy))} }
      raise ArgumentError, 'Subscriptions and installations must be quoted separately, quantity one.' if lines.any? { |line| line['billing_interval'] != 'one_time' || line['product_type'] == 'lightek_instance' } && (lines.size != 1 || lines.first['quantity'] != 1)
      lines
    end
    def self.verify_catalog!(quote)
      current = catalog_lines(quote.site, quote.lines.to_h { |line| [line['product_id'].to_s, line['quantity']] })
      raise ArgumentError, 'Catalog details changed. Create and issue a revised quote.' unless current == quote.lines
    end
    private
    def check_version!(record, version)
      raise ActiveRecord::StaleObjectError.new(record, 'update') unless version.to_s.match?(/\A\d+\z/) && version.to_i == record.lock_version
    end
  end
end
