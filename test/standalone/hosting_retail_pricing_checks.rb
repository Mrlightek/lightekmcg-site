# Actual pricing service and controller with SQLite persistence. Provider
# preflight and authentication are test boundaries.
ENV['DATABASE_URL'] = 'sqlite3::memory:'
require 'rails'
require 'active_record/railtie'
require 'action_controller/railtie'
require 'action_dispatch/testing/integration'
require 'minitest/autorun'
require 'tmpdir'
ROOT = File.expand_path('../..', __dir__)
class PricingTestApp < Rails::Application
  config.root = Dir.mktmpdir('hosting-pricing')
  config.secret_key_base = 'pricing-test-' * 12
  config.eager_load = false
  config.hosts.clear
  config.logger = Logger.new(File::NULL)
end
Rails.application.initialize!
ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Migration.verbose = false
ActiveRecord::Schema.define do
  create_table(:products) { |t| t.integer :price_cents; t.string :product_type }
  create_table(:hosting_packages) { |t| t.references :product; t.boolean :active, default: true; t.integer :monthly_cost_ceiling_cents; t.integer :minimum_margin_cents; t.integer :wholesale_price_cents; t.integer :reseller_minimum_margin_cents, default: 500 }
  create_table(:agreements) { |t| t.integer :price_cents; t.string :processor_reference }
end
class Product < ActiveRecord::Base; end
class Agreement < ActiveRecord::Base; end
class HostingPackage < ActiveRecord::Base
  belongs_to :product
  def snapshot = {'package_id' => id, 'minimum_margin_cents' => minimum_margin_cents}
end
module Gatekeeper
  module Hosting
    module Access; class Denied < StandardError; end; end
    class PackagePurchase
      class << self; attr_accessor :reject, :snapshot; end
      def self.validate!(snapshot:, **)
        self.snapshot = snapshot
        raise Access::Denied, 'Provider quote unavailable' if reject
      end
    end
  end
end
ENV['LIGHTEK_COMMERCE_PROCESSOR_FEE_BPS'] = '300'
ENV['LIGHTEK_COMMERCE_PLATFORM_FEE_BPS'] = '0'
ENV['LIGHTEK_COMMERCE_PROCESSOR_FIXED_CENTS'] = '30'
require ROOT + '/app/services/lightek_commerce/merchant_payouts'
class ApplicationController < ActionController::Base
  def current_user
    Struct.new(:role).new(request.headers['X-Test-Role']) if request.headers['X-Test-Role']
  end
end
module Dashboard; end
require ROOT + '/app/services/gatekeeper/hosting/workspace_plans'
require ROOT + '/app/services/gatekeeper/hosting/retail_pricing'
require ROOT + '/app/controllers/dashboard/hosting_packages_controller'
Rails.application.routes.draw do
  get '/dashboard/hosting/packages', to: proc { [200, {}, ['pricing']] }, as: :dashboard_hosting_packages
  patch '/dashboard/hosting/packages/:id', to: 'dashboard/hosting_packages#update', as: :dashboard_hosting_package
end
class HostingRetailPricingChecks < ActionDispatch::IntegrationTest
  def setup
    Agreement.delete_all; HostingPackage.delete_all; Product.delete_all
    @package = HostingPackage.create!(product: Product.create!(price_cents: 10_000), monthly_cost_ceiling_cents: 2400, minimum_margin_cents: 2000)
    Gatekeeper::Hosting::PackagePurchase.reject = false
    Dashboard::HostingPackagesController.allow_forgery_protection = false
  end
  def change(price, margin: nil, role: 'super_admin', **pricing)
    patch "/dashboard/hosting/packages/#{@package.id}", params: {package: {price_cents: price}.merge(margin.nil? ? {} : {minimum_margin_cents: margin}).merge(pricing)}, headers: {'X-Test-Role' => role}
  end
  def test_price_change_preserves_existing_billing_and_availability
    agreement = Agreement.create!(price_cents: 10_000, processor_reference: 'sub_existing')
    change('4900')
    assert_response :redirect
    assert_equal 4900, @package.product.reload.price_cents
    assert @package.reload.active?
    assert_equal [10_000, 'sub_existing'], agreement.reload.attributes.values_at('price_cents', 'processor_reference')
    assert_match(/Existing subscriptions/, flash[:notice])
  end
  def test_operator_can_lower_personal_price_and_margin_together
    @package.update!(monthly_cost_ceiling_cents: 1200, minimum_margin_cents: 1000)
    agreement = Agreement.create!(price_cents: 2500, processor_reference: 'sub_personal')
    change('1999', margin: '600')
    assert_response :redirect
    assert_equal 1999, @package.product.reload.price_cents
    assert_equal 600, @package.reload.minimum_margin_cents
    assert_equal 600, Gatekeeper::Hosting::PackagePurchase.snapshot.fetch("minimum_margin_cents")
    assert_equal 2500, agreement.reload.price_cents
  end
  def test_rejected_update_rolls_back_margin_and_price
    Gatekeeper::Hosting::PackagePurchase.reject = true
    change('4900', margin: '1000')
    assert_equal 2000, @package.reload.minimum_margin_cents
    assert_equal 10_000, @package.product.reload.price_cents
  end
  def test_lower_margin_still_requires_cost_and_fee_coverage
    change('2500', margin: '100')
    assert_match(/payment fees/, flash[:alert])
    assert_equal 2000, @package.reload.minimum_margin_cents
    assert_equal 10_000, @package.product.reload.price_cents
  end
  def test_invalid_margins_are_rejected_without_changes
    ['0', '-1', '6.00', '', 'oops'].each do |margin|
      change('4900', margin: margin)
      assert_equal 2000, @package.reload.minimum_margin_cents
      assert_equal 10_000, @package.product.reload.price_cents
      assert_match(/whole-cent/, flash[:alert])
    end
  end
  def test_operator_controls_independent_wholesale_price_and_agency_markup
    change('4900', wholesale_price_cents: '4700', reseller_minimum_margin_cents: '1000')
    assert_equal 4900, @package.product.reload.price_cents
    assert_equal 4700, @package.reload.wholesale_price_cents
    assert_equal 1000, @package.reseller_minimum_margin_cents
    change('5100')
    assert_equal 4700, @package.reload.wholesale_price_cents
  end
  def test_wholesale_cost_floor_rolls_back_all_prices
    change('4900', margin: '500', wholesale_price_cents: '2500', reseller_minimum_margin_cents: '1000')
    assert_match(/wholesale price must cover/, flash[:alert])
    assert_equal 10_000, @package.product.reload.price_cents
    assert_nil @package.reload.wholesale_price_cents
    assert_equal 2000, @package.minimum_margin_cents
    assert_equal 500, @package.reseller_minimum_margin_cents
  end
  def test_invalid_or_nonoperator_wholesale_changes_are_rejected
    ['oops', '0', '-1', '19.99'].each do |value|
      change('4900', wholesale_price_cents: value)
      assert_nil @package.reload.wholesale_price_cents
      assert_equal 10_000, @package.product.reload.price_cents
    end
    change('4900', wholesale_price_cents: '4700', role: 'white_label')
    assert_response :forbidden
    assert_nil @package.reload.wholesale_price_cents
    change('4900', reseller_minimum_margin_cents: '-1')
    assert_equal 500, @package.reload.reseller_minimum_margin_cents
  end
  def test_margin_and_payment_fee_floor_is_enforced
    change('4500')
    assert_equal 10_000, @package.product.reload.price_cents
    assert_match(/payment fees/, flash[:alert])
  end
  def test_invalid_whole_cent_prices_are_rejected
    ['49.00', '-1', '0', '', '4oops'].each do |price|
      change(price)
      assert_equal 10_000, @package.product.reload.price_cents
      assert_match(/whole-cent/, flash[:alert])
    end
  end
  def test_failed_provider_preflight_preserves_price
    Gatekeeper::Hosting::PackagePurchase.reject = true
    change('4900')
    assert_equal 10_000, @package.product.reload.price_cents
    assert_match(/Provider quote/, flash[:alert])
  end
  def test_nonoperators_cannot_edit_or_toggle
    ['client', 'white_label', 'member'].each do |role|
      change('4900', margin: '1000', role: role)
      assert_response :forbidden
      assert_equal 10_000, @package.product.reload.price_cents
    end
  end
  def test_existing_availability_toggle_still_works
    patch "/dashboard/hosting/packages/#{@package.id}", headers: {'X-Test-Role' => 'super_admin'}
    assert_response :redirect
    refute @package.reload.active?
    assert_equal 10_000, @package.product.reload.price_cents
  end
  def test_price_changes_require_csrf_protection
    Dashboard::HostingPackagesController.allow_forgery_protection = true
    change('4900')
    assert_response :unprocessable_entity
    assert_equal 10_000, @package.product.reload.price_cents
  ensure
    Dashboard::HostingPackagesController.allow_forgery_protection = false
  end
end
