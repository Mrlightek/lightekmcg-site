require_relative 'commerce_hosting_test'
source = Rails.root.join('db/migrate/20261108190000_create_lightek_resort_reservations.rb').read
source = source.gsub('Migration[8.0]', "Migration[#{ActiveRecord::VERSION::MAJOR >= 8 ? '8.0' : '7.2'}]")
source = source.lines.reject { |line| line.include?("add_column :lightek_commerce_orders, :payment_namespace") }.join
eval(source, TOPLEVEL_BINDING)
class CreateLightekResortReservations
  def add_column(table, column, *args, **options)
    super unless connection.column_exists?(table, column)
  end
end
CreateLightekResortReservations.new.migrate(:up)
require Rails.root.join('app/models/lightek_reservations/resource').to_s
require Rails.root.join('app/services/lightek_reservations/federation/catalog').to_s
module LightekDesign
  module StarterLibrary
    def self.designs = {}
  end
end
class AgencyResellerChecks < CommerceHostingTest
  def self.runnable_methods = public_instance_methods.grep(/^test_reseller_/).map(&:to_s)
  def setup
    super
    @agency = User.create!(role: 'white_label', email_address: 'agency@example.test')
    @store = DymondSite::Site.create!(tenant: @agency, host: 'agency.example.test')
    @base_product = product(name: 'Lightek starter server', product_type: 'lightek_instance', price_cents: 1500, subscription_plan_id: 1)
    @base = HostingPackage.create!(product: @base_product, active: true,
      compute_provider: ComputeProvider.create!(slug: 'linode', health_status: 'healthy'),
      gatekeeper_application_template: GatekeeperApplicationTemplate.create!(name: 'Native', kind: 'native_rails'),
      region: 'us-east', provider_plan: 'g6-nanode-1', monthly_cost_ceiling_cents: 600, minimum_margin_cents: 100)
    @context = Struct.new(:site, :site_id).new(@store, @store.id)
  end
  def offer(**attributes)
    LightekReservations::Federation::Catalog.save!(peer: @context, attributes: {
      source_id: "hosting:#{@base.id}", name: 'Agency premium', price_cents: 2500, published: true,
      package_policy: {'features' => {'studio' => {'enabled' => false}, 'mail' => {'monthly_writes' => 100}}, 'limits' => {'max_sites' => 2}}
    }.merge(attributes))
  end
  def buy(resource)
    LightekCommerce::OrderPlacement.call(site: @store, customer_email: 'client@example.test', quantities: {resource.product_id.to_s => 1})
  end
  def test_reseller_catalog_is_automatic_and_excludes_vendor_costs_and_credentials
    rows = LightekAgency::HostingCatalog.rows
    row = rows.find { |entry| entry['id'] == "hosting:#{@base.id}" }
    assert_equal 1500, row['price_cents']
    assert_equal 1500, row['cost_floor_cents']
    assert_operator row['minimum_price_cents'], :>, 1500
    refute_includes row.keys, 'monthly_cost_ceiling_cents'
    refute_includes row.keys, 'compute_provider_id'
    refute_includes row.keys, 'credential_slug'
    @base.update!(active: false)
    refute LightekAgency::HostingCatalog.rows.any? { |entry| entry['id'] == row['id'] }
  end
  def test_reseller_cannot_materialize_a_foreign_agency_package
    @base_product.update_columns(site_id: @store.id)
    assert_raises(ActiveRecord::RecordNotFound) { offer }
    refute LightekReservations::Resource.exists?(product: @base_product)
  end
  def test_reseller_product_uses_source_infrastructure_and_freezes_full_wholesale_charge
    resource = offer
    assert_equal 1500, resource.cost_floor_cents
    assert_equal @base.id, resource.product.source_hosting_package_id
    assert_equal 'month', resource.product.billing_interval
    order = buy(resource)
    snapshot = order.items.sole.purchase_snapshot
    assert_equal @base.id, snapshot.dig('hosting', 'package_id')
    assert_equal 1500, snapshot.dig('hosting', 'platform_charge_cents')
    assert_equal false, snapshot.dig('managed_package', 'policy', 'features', 'studio', 'enabled')
    assert_equal 100, snapshot.dig('managed_package', 'policy', 'features', 'mail', 'monthly_writes')
    assert_equal 2, snapshot.dig('managed_package', 'policy', 'limits', 'max_sites')
    quote = LightekCommerce::MerchantPayouts.fee_quote(order)
    assert_equal 1500, quote[:infrastructure_reserve_cents]
    assert_equal 2500 - 1500 - quote[:processor_reserve_cents] - quote[:platform_fee_cents], quote[:net_cents]
    @base_product.update!(price_cents: 3000)
    assert_equal 1500, order.items.sole.reload.purchase_snapshot.dig('hosting', 'platform_charge_cents')
    assert_raises(LightekCommerce::OrderPlacement::Invalid) { buy(resource) }
  end
  def test_reseller_cannot_undercut_lightek_reprice_a_plan_or_expand_features
    assert_raises(ArgumentError) { offer(price_cents: 1500) }
    resource = offer
    refute resource.product.update(price_cents: 1500)
    assert_raises(ActiveRecord::RecordInvalid) { resource.product.update!(subscription_plan_id: 99) }
    @base_product.update!(package_policy: {'features' => {'studio' => {'enabled' => false, 'monthly_writes' => 10}}, 'limits' => {'max_sites' => 2}})
    assert_raises(LightekAgency::PackagePolicy::Denied) { offer(package_policy: {'features' => {'studio' => {'enabled' => true}}}) }
    assert_raises(LightekAgency::PackagePolicy::Denied) { offer(package_policy: {'limits' => {'max_sites' => 3}}) }
    assert_raises(LightekAgency::PackagePolicy::Denied) { offer(package_policy: {'limits' => {'max_sites' => ''}}) }
    assert_raises(LightekAgency::PackagePolicy::Denied) { offer(package_policy: {'features' => {'studio' => {'monthly_writes' => 11}}}) }
  end
  def test_reseller_offer_ids_are_scoped_to_each_agency
    resource = offer
    foreign = User.create!(role: 'white_label', email_address: 'foreign@example.test')
    foreign_site = DymondSite::Site.create!(tenant: foreign, host: 'foreign.example.test')
    @context = Struct.new(:site, :site_id).new(foreign_site, foreign_site.id)
    assert_raises(ActiveRecord::RecordNotFound) { offer(id: resource.id) }
    assert_equal @store.id, resource.reload.site_id
  end
  def test_reseller_policy_is_canonical_and_rejects_unknown_or_invalid_limits
    parent = LightekAgency::PackagePolicy.defaults
    child = LightekAgency::PackagePolicy.restrict!(upstream: parent, requested: {'features' => {'studio' => {'enabled' => false, 'monthly_writes' => 0}}})
    assert_equal false, child.dig('features', 'studio', 'enabled')
    assert_nil child.dig('features', 'mail', 'monthly_writes')
    assert_equal LightekAgency::PackagePolicy.digest(child), LightekAgency::PackagePolicy.digest(child.to_a.reverse.to_h)
    [{'limits' => {'max_users' => -1}}, {'features' => {'arbitrary_shell' => {'enabled' => true}}}, {'limits' => {'max_sites' => '2.5'}}].each do |bad|
      assert_raises(LightekAgency::PackagePolicy::Denied) { LightekAgency::PackagePolicy.normalize(bad) }
    end
  end
end
