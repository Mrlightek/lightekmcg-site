module LightekAgency
  class HostingCatalog
    def self.materialize!(key)
      package = HostingPackage.available.find(key.to_s.delete_prefix('hosting:'))
      raise ActiveRecord::RecordNotFound unless package.product.site.tenant&.role == 'super_admin'
      package.with_lock do
        product = package.product
        resource = LightekReservations::Resource.find_or_initialize_by(product: product, source_resource_id: nil, kind: 'server')
        resource.update!(site: product.site, name: product.name, description: product.description.to_s.first(3000), published: true,
          billing_interval: 'monthly', timezone: 'UTC', notice_minutes: 0,
          cost_floor_cents: package.monthly_cost_ceiling_cents,
          compute: {'region' => package.region, 'plan' => package.provider_plan, 'image' => 'linode/ubuntu24.04', 'monthly_cost_cents' => package.monthly_cost_ceiling_cents})
        resource
      end
    end
    def self.rows
      packages = HostingPackage.available.includes(product: :site).to_a.select { |p| p.product.site.tenant&.role == 'super_admin' }
      legacy = LightekReservations::Federation::Catalog.approved.where.not(product_id: HostingPackage.select(:product_id))
      legacy.map { |resource| LightekReservations::Federation::Catalog.serialize(resource) } + packages.map do |package|
        product = package.product
        {'id' => "hosting:#{package.id}", 'name' => product.name, 'description' => product.short_description,
          'price_cents' => product.price_cents, 'cost_floor_cents' => product.price_cents,
          'minimum_price_cents' => LightekCommerce::MerchantPayouts.minimum_charge_cents(product.price_cents),
          'billing_interval' => 'monthly', 'package_policy' => PackagePolicy.for_product(product)}
      end
    end
  end
end
