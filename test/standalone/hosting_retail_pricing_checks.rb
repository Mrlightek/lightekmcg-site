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
  create_table(:products) { |t| t.integer :price_cents }
  create_table(:hosting_packages) { |t| t.references :product; t.boolean :active, default: true; t.integer :monthly_cost_ceiling_cents; t.integer :minimum_margin_cents }
  create_table(:agreements) { |t| t.integer :price_cents; t.string :processor_reference }
end
class Product < ActiveRecord::Base; end
class Agreement < ActiveRecord::Base; end
class HostingPackage < ActiveRecord::Base
  belongs_to :product
  def snapshot = {'package_id' => id}
end
module Gatekeeper
  module Hosting
    module Access; class Denied < StandardError; end; end
    class PackagePurchase
      class << self; attr_accessor :reject; end
      def self.validate!(**)
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
  def change(price, role: 'super_admin')
    patch "/dashboard/hosting/packages/#{@package.id}", params: {package: {price_cents: price}}, headers: {'X-Test-Role' => role}
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
      change('4900', role: role)
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
