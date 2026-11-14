require_relative 'enterprise_onboarding_checks'
ActiveRecord::Schema.define do
  create_table(:dymond_site_pages) { |t| t.integer :site_id; t.string :title; t.string :slug; t.integer :position; t.boolean :published, default: false }
  create_table(:dymond_site_sections) { |t| t.integer :page_id; t.string :kind; t.integer :position; t.json :data, default: {} }
  create_table(:user_feature_entitlements) { |t| t.integer :user_id; t.string :feature_slug; t.string :source; t.boolean :active, default: true; t.datetime :revoked_at }
  create_table(:lightek_commerce_products) { |t| t.integer :site_id; t.string :name; t.string :product_type; t.boolean :published; t.integer :subscription_plan_id; t.integer :price_cents; t.string :billing_interval }
  add_column :lightek_commerce_orders, :hosting_owner_id, :integer
  add_column :lightek_commerce_orders, :payment_reference, :string
  add_column :lightek_commerce_orders, :provisioning_state, :string
end
module DymondSite
  class Page < ApplicationRecord
    self.table_name = 'dymond_site_pages'
    belongs_to :site, class_name: 'DymondSite::Site'
    has_many :sections, class_name: 'DymondSite::Section', dependent: :destroy
    scope :published, -> { where(published: true) }
  end
  class Section < ApplicationRecord
    self.table_name = 'dymond_site_sections'
    belongs_to :page, class_name: 'DymondSite::Page'
  end
  class Site
    has_many :pages, class_name: 'DymondSite::Page', dependent: :destroy
    def nav_menu = nil
  end
end
class User
  def bank_accounts = User.none
  def invoices = User.none
  def payouts = User.none
  def subscription = nil
end
module LightekCommerce
  class Product < ApplicationRecord
    self.table_name = 'lightek_commerce_products'
    belongs_to :site, class_name: 'DymondSite::Site'
    scope :visible, -> { where(published: true) }
  end
  class Order
    belongs_to :hosting_owner, class_name: 'User', optional: true
    belongs_to :site, class_name: 'DymondSite::Site', optional: true
  end
end
ActiveRecord::Base.connection.add_column(:lightek_commerce_orders, :site_id, :integer) unless ActiveRecord::Base.connection.column_exists?(:lightek_commerce_orders, :site_id)
LightekCommerce::Order.reset_column_information
require ROOT.join('app/models/user_feature_entitlement')
%w[demo_setting demo_request].each { |file| require ROOT.join("app/models/lightek_agency/#{file}") }
LightekAgency::DemoRequest.generated_token_verifier = User.generated_token_verifier
%w[demo_content demo_upgrade demo_cleanup].each { |file| require ROOT.join("app/services/lightek_agency/#{file}") }
class ApplicationJob
  def self.retry_on(*) = nil
end
%w[demo_cleanup_job demo_sweep_job].each { |file| require ROOT.join("app/jobs/lightek_agency/#{file}") }
require ROOT.join('app/mailers/lightek_agency/demo_request_mailer')
require ROOT.join('app/controllers/dashboard/demos_controller')
require ROOT.join('app/controllers/demo_requests_controller')
Dashboard::DemosController.layout false
DemoRequestsController.layout false
module LightekCommerce
  class InstallationCheckout
    class Invalid < StandardError; end
    def self.reserve!(**) = raise('Replace payment boundary in this fixture')
  end
  class StripeCheckout
    class Unavailable < StandardError; end
  end
  class OrderPlacement
    class Invalid < StandardError; end
  end
end

class AgencyDemoChecks < EnterpriseOnboardingChecks
  def self.runnable_methods = public_instance_methods.grep(/^test_demo_/).map(&:to_s)
  def setup
    super
    DymondSite::Section.delete_all; DymondSite::Page.delete_all
    LightekCommerce::Product.delete_all; UserFeatureEntitlement.delete_all
    LightekAgency::DemoCleanupJob.enqueued = []
    @agency_site = DymondSite::Site.create!(tenant: @employer, name: 'Agency site', host: 'example.test')
    @product = LightekCommerce::Product.create!(site: @agency_site, name: 'Full instance', published: true,
      product_type: 'lightek_instance', subscription_plan_id: 1, price_cents: 10000, billing_interval: 'month')
    @setting = LightekAgency::DemoSetting.create!(agency: @employer, public_site: @agency_site, public_enabled: true, upgrade_product: @product)
  end
  def make_demo
    LightekAgency::Demos.create!(agency: @employer, values: {first_name: 'Demo', last_name: 'Client', email_address: "demo-#{SecureRandom.hex(3)}@example.test"})
  end
  def test_demo_is_local_scoped_timed_and_invites_a_client_without_admin_escalation
    before = GatekeeperNode.count
    demo = make_demo
    assert_equal 'client', demo.client.role
    assert_equal @employer.id, demo.client.agency_id
    assert_equal demo.client, demo.site.tenant
    assert_equal demo.public_id, demo.site.manifest['agency_demo']
    assert_equal 1, demo.site.pages.count
    assert_in_delta 14.days.from_now.to_i, demo.expires_at.to_i, 2
    assert_includes LightekAgency::DemoCleanupJob.enqueued, [demo.id]
    assert_equal before, GatekeeperNode.count
    assert ActiveJob::Base.queue_adapter.enqueued_jobs.any?
  end
  def test_demo_expiry_blocks_site_access_before_cleanup_runs
    demo = make_demo
    assert LightekSettings::WebsiteIdentity.sites_for(demo.client).exists?(id: demo.site_id)
    travel 15.days
    refute demo.reload.active?
    refute LightekSettings::WebsiteIdentity.sites_for(demo.client).exists?(id: demo.site_id)
    refute LightekAgency::Access.sites_for(demo.client).exists?(id: demo.site_id)
  end
  def test_demo_cannot_attach_another_agencys_client_or_exceed_capacity
    assert_raises(LightekAgency::Demos::Invalid) { LightekAgency::Demos.create!(agency: @employer, existing_client: @other, values: {}) }
    @setting.update!(max_active: 1)
    make_demo
    assert_raises(LightekAgency::Demos::Invalid) { make_demo }
  end
  def test_demo_public_request_queues_email_without_allocating_and_requires_confirmation
    before = LightekAgency::Demo.count
    post request_demo_path, params: {demo_request: {first_name: 'Public', last_name: 'Client', email_address: 'public@example.test'}}
    assert_redirected_to request_demo_path
    request = LightekAgency::DemoRequest.last
    assert_equal before, LightekAgency::Demo.count
    assert ActiveJob::Base.queue_adapter.enqueued_jobs.any?
    token = request.generate_token_for(:confirmation)
    get confirm_demo_request_path(token)
    assert_response :success
    assert_equal before, LightekAgency::Demo.count
    post activate_demo_request_path(token)
    assert_response :redirect
    assert_match %r{/account/setup/}, response.location
    assert_equal before + 1, LightekAgency::Demo.count
    assert_equal 'activated', request.reload.status
    assert_raises(ActiveSupport::MessageVerifier::InvalidSignature) { LightekAgency::DemoRequest.find_by_token_for!(:confirmation, token) }
  end
  def test_demo_public_existing_identity_cannot_be_claimed_or_reparented
    request = LightekAgency::DemoRequest.create!(agency: @employer, first_name: 'Other', last_name: 'Owner', email_address: @other.email_address)
    token = request.generate_token_for(:confirmation)
    post activate_demo_request_path(token)
    assert_redirected_to new_session_path(return_to: confirm_demo_request_path(token))
    assert_nil @other.reload.agency_id
    assert_nil request.reload.demo
  end
  def test_demo_public_requests_are_bound_to_the_enabled_agency_hostname
    request = LightekAgency::DemoRequest.create!(agency: @employer, first_name: 'New', last_name: 'Person', email_address: 'new@example.test')
    @setting.update!(public_enabled: false)
    assert_raises(ActiveRecord::RecordNotFound) { post activate_demo_request_path(request.generate_token_for(:confirmation)) }
    assert_equal 0, LightekAgency::Demo.count
  end
  def test_demo_upgrade_snapshot_is_scoped_and_import_is_idempotent
    demo = make_demo
    content = LightekAgency::DemoContent.export(demo)
    refute_includes JSON.generate(content), 'password'
    refute_includes JSON.generate(content), @agency_site.host
    target = DymondSite::Site.create!(tenant: @other, name: 'New instance', host: 'new.example.test', manifest: {'lightek_website_bootstrap' => 1})
    digest = LightekAgency::DemoContent.install!(site: target, content: content)
    assert_equal digest, target.reload.manifest['demo_content_digest']
    assert_equal demo.site.pages.first.sections.first.data, target.pages.first.sections.first.data
    target.pages.first.update!(title: 'Owner edit')
    LightekAgency::DemoContent.install!(site: target, content: content)
    assert_equal 'Owner edit', target.pages.first.reload.title
    assert_raises(ArgumentError) { LightekAgency::DemoContent.install!(site: target, content: content.merge('name' => 'Changed')) }
  end
  def test_demo_upgrade_requires_owner_payment_and_verified_readiness_before_cleanup
    demo = make_demo
    order = LightekCommerce::Order.create!(customer_email: demo.client.email_address, hosting_owner: demo.client,
      agency_demo_id: demo.id, demo_content: LightekAgency::DemoContent.export(demo), status: 'pending_payment')
    demo.update!(upgrade_order: order)
    assert_raises(LightekAgency::Demos::Invalid) { LightekAgency::DemoUpgrade.content_for(order) }
    assert_raises(LightekAgency::Demos::Invalid) { LightekAgency::DemoUpgrade.reserve!(demo: demo, actor: @other, checkout_key: SecureRandom.uuid) }
    order.update!(status: 'paid', paid_at: Time.current, provisioning_state: 'failed')
    assert_raises(LightekAgency::Demos::Invalid) { LightekAgency::DemoUpgrade.complete!(order) }
    LightekAgency::DemoCleanup.call!(demo)
    assert demo.reload.site
    order.update!(provisioning_state: 'ready', provisioned_at: Time.current)
    LightekAgency::DemoUpgrade.complete!(order)
    LightekAgency::DemoCleanupJob.new.perform(demo.id)
    assert demo.reload.cleaned_at
    assert_equal 'converted', demo.status
    assert User.exists?(id: order.hosting_owner_id), 'Paid client portal identity must remain'
    assert LightekCommerce::Order.exists?(id: order.id)
  end
  def test_demo_upgrade_reuses_one_order_and_freezes_only_the_owners_website
    demo = make_demo
    actor = demo.client
    order = LightekCommerce::Order.create!(customer_email: actor.email_address, status: 'pending_payment')
    calls = 0
    LightekCommerce::InstallationCheckout.stub(:reserve!, ->(**args) {
      calls += 1
      assert_equal actor.id, args.fetch(:actor).id
      assert_equal @product.id, args.fetch(:product).id
      order
    }) do
      first = LightekAgency::DemoUpgrade.reserve!(demo: demo, actor: actor, checkout_key: SecureRandom.uuid)
      second = LightekAgency::DemoUpgrade.reserve!(demo: demo, actor: actor, checkout_key: SecureRandom.uuid)
      assert_equal first.id, second.id
    end
    assert_equal 1, calls
    assert_equal demo.id, order.reload.agency_demo_id
    assert_equal actor.id, order.hosting_owner_id
    assert_equal demo.public_id, order.demo_content['demo_id']
    assert_equal 'upgrading', demo.reload.status
  end
  def test_demo_public_activation_remains_csrf_protected
    request = LightekAgency::DemoRequest.create!(agency: @employer, first_name: 'New', last_name: 'Client', email_address: 'csrf@example.test')
    DemoRequestsController.allow_forgery_protection = true
    assert_raises(ActionController::InvalidAuthenticityToken) { post activate_demo_request_path(request.generate_token_for(:confirmation)) }
    assert_nil request.reload.demo
  ensure
    DemoRequestsController.allow_forgery_protection = false
  end
  def test_demo_expiry_cleanup_removes_only_its_workspace_and_empty_demo_identity
    demo = make_demo
    site_id = demo.site_id
    client_id = demo.client_id
    LightekAgency::DemoCleanup.call!(demo)
    assert DymondSite::Site.exists?(id: site_id)
    travel 15.days
    LightekAgency::DemoCleanupJob.new.perform(demo.id)
    refute DymondSite::Site.exists?(id: site_id)
    refute User.exists?(id: client_id)
    assert User.exists?(id: @employer.id)
    assert DymondSite::Site.exists?(id: @agency_site.id)
    assert_equal 'expired', demo.reload.status
    assert_nil demo.client_id
    LightekAgency::DemoCleanupJob.new.perform(demo.id)
    assert demo.reload.cleaned_at
  end
  def test_demo_sweeper_recovers_missed_jobs_and_side_effects_are_blocked
    demo = make_demo
    assert_raises(LightekAgency::Demos::Invalid) { LightekAgency::Demos.ensure_live_site!(demo.site) }
    assert LightekAgency::Demos.ensure_live_site!(@agency_site).nil?
    LightekAgency::DemoCleanupJob.enqueued = []
    travel 15.days
    LightekAgency::DemoSweepJob.new.perform
    assert_equal [[demo.id]], LightekAgency::DemoCleanupJob.enqueued
  end
end
