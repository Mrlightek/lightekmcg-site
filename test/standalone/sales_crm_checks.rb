# Real migration, models, service transactions, routes, controller and native views.
# Private Dashboard authentication/layout is a fixture; provider calls are absent.
require 'active_record'
require 'active_support/all'
require 'action_controller/railtie'
require 'action_dispatch/testing/integration'
require 'minitest/autorun'
require 'tmpdir'
require 'pathname'
ROOT = Pathname.new(File.expand_path('../..', __dir__))
class SalesHarness < Rails::Application
  config.root = Dir.mktmpdir('sales-http-')
  config.eager_load = false
  config.secret_key_base = 'sales-test-only-' * 8
  config.hosts.clear
  config.cache_store = :memory_store
  config.logger = Logger.new(File::NULL)
  config.action_dispatch.show_exceptions = :none
  config.action_controller.allow_forgery_protection = true
  config.autoload_paths = []
end
SalesHarness.initialize!
ActiveRecord::Base.establish_connection(ENV.fetch('SALES_DATABASE_URL', 'sqlite3::memory:'))
ActiveRecord::Migration.verbose = false
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
ActiveRecord::Schema.define do
  create_table(:users, force: :cascade) { |t| t.string :email_address; t.string :role }
  create_table(:dymond_site_sites, force: :cascade) { |t| t.string :name; t.string :host; t.references :tenant, polymorphic: true }
  create_table(:lightek_marketing_contacts, force: :cascade) do |t|
    t.references :site; t.string :email; t.datetime :subscribed_at; t.datetime :unsubscribed_at; t.timestamps
  end
  add_index :lightek_marketing_contacts, [:site_id, :email], unique: true, name: 'idx_test_marketing_email'
  create_table(:lightek_agency_site_memberships, force: :cascade) { |t| t.references :site; t.references :user; t.references :granted_by; t.string :role }
end
require ROOT.join('db/migrate/20261115013000_create_lightek_sales')
CreateLightekSales.new.migrate(:up)
class User < ApplicationRecord; end
module DymondSite
  class Site < ApplicationRecord
    self.table_name = 'dymond_site_sites'
    belongs_to :tenant, polymorphic: true
  end
end
module LightekSettings
  class WebsiteIdentity
    def self.sites_for(actor)
      return DymondSite::Site.all if actor&.role == 'super_admin'
      return DymondSite::Site.none unless actor&.role.in?(%w[admin white_label client])
      DymondSite::Site.where(tenant: actor)
    end
    def self.available_demo_scope(scope) = scope
  end
end
require ROOT.join('app/models/lightek_agency/site_membership')
require ROOT.join('app/services/lightek_agency/access')
require ROOT.join('app/services/lightek_sales/access')
require ROOT.join('app/models/concerns/sales_site_record')
require ROOT.join('app/models/lightek_marketing/contact')
%w[account opportunity lead routing_rule activity].each { |name| require ROOT.join("app/models/lightek_sales/#{name}") }
%w[workspace forecast].each { |name| require ROOT.join("app/services/lightek_sales/#{name}") }
require ROOT.join('app/services/lightek_agency/package_features')
require_relative 'sales_intake_support'
module Dashboard
  class SettingsHomeController < ActionController::Base
    before_action :require_settings_operator!, except: :csrf
    protect_from_forgery with: :exception
    helper_method :current_user
    def current_user = User.find_by(id: request.headers['X-Test-User'])
    def require_settings_operator! = head(:forbidden)
    def csrf = render(json: {token: form_authenticity_token})
  end
end
require ROOT.join('app/controllers/dashboard/commerce_base_controller')
require ROOT.join('app/controllers/dashboard/sales_controller')
require ROOT.join('app/controllers/dashboard/sales_quotes_controller')
require ROOT.join('app/controllers/dashboard/sales_intake_controller')
require ROOT.join('app/controllers/dashboard/sales_tasks_controller')
[Dashboard::SalesIntakeController, Dashboard::SalesTasksController].each { |klass| klass.prepend_view_path ROOT.join('app/views'); klass.layout false }
Dashboard::SalesController.prepend_view_path ROOT.join('app/views')
Dashboard::SalesController.layout false
SalesHarness.routes.draw do
  eval(ROOT.join('config/routes/sales_quotes.rb').read, binding)
  eval(ROOT.join('config/routes/sales.rb').read, binding)
  get '/orders', to: 'dashboard/sales#index', as: :dashboard_commerce_orders
  get '/customers/history', to: 'dashboard/sales#index', as: :history_dashboard_customers
  get '/csrf', to: 'dashboard/settings_home#csrf'
  %w[business_hub website_designs media_studio marketing_campaigns commerce customers pwa].each do |name|
    get "/workspace/#{name}", to: 'dashboard/sales#index', as: "dashboard_#{name}"
  end
end
class SalesCrmChecks < ActionDispatch::IntegrationTest
  include SalesHarness.routes.url_helpers
  def app = SalesHarness
  def setup
    Rails.cache.clear
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    LightekAgency::PackagePolicy.allowed = true
    LightekAgency::PackagePolicy.reserved = LightekAgency::PackagePolicy.released = 0
    [LightekSales::Quote, LightekCommerce::OrderItem, LightekCommerce::Order, LightekCommerce::Product, LightekPeople::LifecycleCase, LightekSales::Task, LightekSales::IntakeEntry, LightekSales::IntakeRule, WebsiteTemplateInquiry, DymondSite::Section, DymondSite::Page].each(&:delete_all)
    [LightekSales::Activity, LightekSales::RoutingRule, LightekSales::Lead, LightekSales::Opportunity,
     LightekMarketing::Contact, LightekSales::Account, LightekAgency::SiteMembership, DymondSite::Site, User].each(&:delete_all)
    @owner = User.create!(email_address: 'owner@example.test', role: 'admin')
    @other = User.create!(email_address: 'other@example.test', role: 'admin')
    @member = User.create!(email_address: 'sales@example.test', role: 'employee')
    @designer = User.create!(email_address: 'design@example.test', role: 'client')
    @site = DymondSite::Site.create!(name: 'Lightek Test Business', host: 'lightek.test', tenant: @owner)
    @foreign_site = DymondSite::Site.create!(name: 'Other business', host: 'other.test', tenant: @other)
    LightekAgency::SiteMembership.create!(site: @site, user: @member, granted_by: @owner, role: 'marketer')
    LightekAgency::SiteMembership.create!(site: @site, user: @designer, granted_by: @owner, role: 'designer')
    @workspace = LightekSales::Workspace.new(actor: @owner, site: @site)
    host! 'sales.test'
  end
  def headers(actor = @owner) = {'X-Test-User' => actor.id.to_s}
  def token(actor = @owner)
    get '/csrf', headers: headers(actor)
    JSON.parse(response.body).fetch('token')
  end
  def lead(**values)
    @workspace.save!('lead', {name: 'Jamie Buyer', email: 'jamie@example.test', company: 'North Studio', status: 'qualified', next_step: 'Review the scope', follow_up_on: Date.current}.merge(values))
  end
  def company(site = @site, **values)
    LightekSales::Account.create!({site: site, name: 'North Studio', owner: site.tenant}.merge(values))
  end
  def deal(**values)
    LightekSales::Opportunity.create!({site: @site, account: values.fetch(:account) { company }, name: 'Managed services', amount_cents: 100_000, probability: 60,
      stage: 'proposal', close_on: Date.current, owner: @owner, next_step: 'Review proposal', follow_up_on: Date.current}.merge(values))
  end
  def test_conversion_reuses_company_and_marketing_contact_preserves_consent_and_is_idempotent
    account = company
    contact = LightekMarketing::Contact.create!(site: @site, email: 'jamie@example.test', subscribed_at: 2.days.ago, unsubscribed_at: 1.day.ago)
    consent = contact.attributes.slice('subscribed_at', 'unsubscribed_at')
    prospect = lead
    first = @workspace.convert!(prospect.id, {name: 'Launch services', amount: '1250.55', currency: 'USD', close_on: Date.current + 30}, lock_version: prospect.lock_version)
    assert_equal 125055, first.amount_cents
    assert_equal account, first.account
    assert_equal contact, first.contact
    assert_equal 30, first.probability
    assert_equal consent, contact.reload.attributes.slice('subscribed_at', 'unsubscribed_at')
    assert_equal 'Review the scope', first.next_step
    assert_equal 'converted', prospect.reload.status
    assert_equal first, @workspace.convert!(prospect.id, {}, lock_version: 0)
    assert_equal 1, LightekSales::Opportunity.count
    assert_equal 1, LightekSales::Account.count
    assert_equal 1, LightekMarketing::Contact.count
    assert_equal 1, LightekSales::Activity.where(record: prospect, kind: 'converted').count
    assert_raises(ActiveRecord::RecordInvalid) { prospect.update!(name: 'Changed') }
  end
  def test_failed_conversion_rolls_back_all_records_and_cannot_convert_unqualified_lead
    prospect = lead(status: 'new')
    assert_raises(ArgumentError) { @workspace.convert!(prospect.id, {}, lock_version: 0) }
    prospect.update!(status: 'qualified')
    counts = [LightekSales::Account.count, LightekMarketing::Contact.count, LightekSales::Activity.count]
    assert_raises(ActiveRecord::RecordInvalid) { @workspace.convert!(prospect.id, {name: '', currency: 'USD', close_on: Date.current}, lock_version: prospect.lock_version) }
    assert_equal counts, [LightekSales::Account.count, LightekMarketing::Contact.count, LightekSales::Activity.count]
    assert_nil prospect.reload.converted_at
    assert_raises(ActiveRecord::StaleObjectError) { @workspace.convert!(prospect.id, {}, lock_version: 99) }
  end
  def test_conversion_keeps_existing_contacts_company_and_never_infers_marketing_opt_in
    existing = company(name: 'Existing relationship')
    contact = LightekMarketing::Contact.create!(site: @site, email: 'jamie@example.test', sales_account: existing)
    prospect = lead
    converted = @workspace.convert!(prospect.id, {name: 'Expansion', close_on: Date.current}, lock_version: 0)
    assert_equal existing, converted.account
    assert_equal existing, contact.reload.sales_account
    assert_nil contact.subscribed_at
    assert_equal 1, LightekSales::Account.count
  end
  def test_routing_uses_normalized_source_and_ignores_revoked_or_foreign_owners
    @workspace.save!('routing_rule', {source: ' Referral ', owner_id: @member.id})
    assert_equal @member.id, lead(source: 'REFERRAL').owner_id
    LightekAgency::SiteMembership.where(user: @member).delete_all
    assert_equal @owner.id, lead(email: 'second@example.test', source: 'referral').owner_id
    assert_raises(ActiveRecord::RecordInvalid) { @workspace.save!('routing_rule', {source: 'event', owner_id: @other.id}) }
    assert_raises(ActiveRecord::RecordInvalid) { lead(email: 'third@example.test', owner_id: @designer.id) }
  end
  def test_forecast_separates_currencies_months_categories_and_closed_statuses
    account = company
    base = {site: @site, account: account, name: 'Forecast', close_on: Date.current, owner: @owner}
    make = ->(**values) { LightekSales::Opportunity.create!(base.merge(values)) }
    make.call(amount_cents: 10_001, stage: 'proposal', probability: 50, forecast_category: 'pipeline')
    make.call(amount_cents: 20_000, stage: 'proposal', probability: 80, forecast_category: 'commit')
    make.call(amount_cents: 30_000, stage: 'negotiation', probability: 20, forecast_category: 'best_case')
    make.call(amount_cents: 90_000, forecast_category: 'omitted')
    make.call(amount_cents: 12_000, stage: 'closed_won')
    make.call(amount_cents: 11_000, stage: 'closed_lost', loss_reason: 'Timing')
    make.call(amount_cents: 99_000, close_on: Date.current.next_month)
    make.call(amount_cents: 1_000, currency: 'EUR', probability: 10)
    rows = LightekSales::Forecast.call(@workspace.scope('opportunity')).index_by { |row| row[:currency] }
    assert_equal [60_001, 27_001, 20_000, 50_000, 12_000, 11_000], rows['USD'].values_at(:open_cents, :weighted_cents, :commit_cents, :best_case_cents, :won_cents, :lost_cents)
    assert_equal 100, rows['EUR'][:weighted_cents]
    assert_equal 100, LightekSales::Opportunity.find_by(stage: 'closed_won').probability
    assert_equal 0, LightekSales::Opportunity.find_by(stage: 'closed_lost').probability
  end
  def test_cross_site_relations_and_stale_updates_are_rejected
    other = company(@foreign_site)
    assert_raises(ActiveRecord::RecordInvalid) { deal(account: other) }
    contact = LightekMarketing::Contact.new(site: @site, email: 'invalid@example.test', sales_account: other)
    refute contact.valid?
    row = lead
    @workspace.save!('lead', {next_step: 'Updated'}, id: row.id, lock_version: row.lock_version)
    assert_raises(ActiveRecord::StaleObjectError) { @workspace.save!('lead', {next_step: 'Old draft'}, id: row.id, lock_version: row.lock_version) }
    assert_equal 'Updated', row.reload.next_step
    assert_raises(ActiveRecord::RecordNotFound) { LightekSales::Workspace.new(actor: @other, site: @site) }
    assert_raises(ActiveRecord::RecordNotFound) { LightekSales::Workspace.new(actor: @designer, site: @site) }
    assert_raises(ActiveRecord::RecordNotFound) { @workspace.find('account', other.id) }
  end
  def test_contact_edits_preserve_email_identity_and_marketing_permission
    row = @workspace.save!('contact', {email: 'consent@example.test', name: 'Buyer'})
    assert_nil row.subscribed_at
    assert_raises(ArgumentError) { @workspace.save!('contact', {email: 'other@example.test'}, id: row.id, lock_version: 0) }
    @workspace.save!('contact', {name: 'Known buyer'}, id: row.id, lock_version: 0)
    assert_equal 'consent@example.test', row.reload.email
    assert_nil row.subscribed_at
  end
  def test_http_crud_forms_activities_csrf_and_tenant_access
    csrf = token
    post dashboard_sales_records_path(kind: 'lead', site_id: @site.id), params: {record: {name: 'Jamie', company: 'North Studio', email: 'jamie@example.test'}}, headers: headers.merge('X-CSRF-Token' => csrf)
    assert_response :see_other
    row = LightekSales::Lead.last
    get response.location, headers: headers
    assert_response :ok
    assert_includes response.body, 'Next step'
    assert_includes response.body, 'Convert qualified lead'
    patch record_path('lead', row), params: {record: {status: 'qualified', lock_version: row.lock_version}}, headers: headers.merge('X-CSRF-Token' => csrf)
    assert_response :see_other
    assert_equal 'qualified', row.reload.status
    post convert_dashboard_sales_lead_path(id: row.id, site_id: @site.id), params: {conversion: {name: 'Agency launch', amount: '2500.00', close_on: Date.current, lock_version: row.lock_version}}, headers: headers.merge('X-CSRF-Token' => csrf)
    assert_response :see_other
    opportunity = row.reload.opportunity
    assert_equal 250000, opportunity.amount_cents
    post dashboard_sales_activities_path(kind: 'opportunity', id: opportunity.id, site_id: @site.id), params: {activity: {kind: 'call', body: '<script>alert(1)</script> Agreed to review.'}}, headers: headers.merge('X-CSRF-Token' => csrf)
    assert_response :see_other
    get record_path('opportunity', opportunity), headers: headers
    assert_response :ok
    assert_includes response.body, '&lt;script&gt;alert(1)&lt;/script&gt;'
    assert_raises(ActionController::InvalidAuthenticityToken) do
      post dashboard_sales_activities_path(kind: 'opportunity', id: opportunity.id, site_id: @site.id), params: {activity: {kind: 'note', body: 'No CSRF'}}, headers: headers
    end
    assert_equal 0, LightekSales::Activity.where(body: 'No CSRF').count
    assert_raises(ActiveRecord::RecordNotFound) { get record_path('lead', row), headers: headers(@other) }
    assert_raises(ActiveRecord::RecordNotFound) { get record_path('lead', row), headers: headers(@designer) }
    get record_path('lead', row), headers: headers(@member)
    assert_response :ok
    assert_raises(ActiveRecord::RecordNotFound) { get new_dashboard_sales_record_path(kind: 'routing_rule', site_id: @site.id), headers: headers(@member) }
  end
  def test_deal_stage_transitions_membership_revocation_and_contact_company_integrity
    row = deal
    assert_equal 60, row.probability
    @workspace.save!('opportunity', {stage: 'negotiation'}, id: row.id, lock_version: row.lock_version)
    assert_equal 80, row.reload.probability
    assert_raises(ActiveRecord::RecordInvalid) { @workspace.save!('opportunity', {stage: 'closed_lost', loss_reason: '  '}, id: row.id, lock_version: row.lock_version) }
    @workspace.save!('opportunity', {stage: 'closed_won', probability: 15}, id: row.id, lock_version: row.lock_version)
    assert_equal 100, row.reload.probability
    assert row.closed_at
    @workspace.save!('opportunity', {stage: 'discovery'}, id: row.id, lock_version: row.lock_version)
    assert_nil row.reload.closed_at
    assert_equal 10, row.probability
    contact = @workspace.save!('contact', {email: 'linked@example.test', sales_account_id: row.account_id, sales_owner_id: @member.id})
    row.update!(contact: contact)
    other_company = company(name: 'Different company')
    assert_raises(ActiveRecord::RecordInvalid) { @workspace.save!('contact', {sales_account_id: other_company.id}, id: contact.id, lock_version: contact.lock_version) }
    LightekAgency::SiteMembership.where(user: @member).delete_all
    # Removing sales access must never prevent the marketing unsubscribe path.
    contact.reload.update!(unsubscribed_at: Time.current)
    assert contact.unsubscribed_at
    assert_raises(ActiveRecord::RecordNotFound) { LightekSales::Workspace.new(actor: @member, site: @site) }
  end
  def test_http_foreign_relations_routing_access_and_invalid_amounts
    csrf = token
    foreign = company(@foreign_site, name: 'Private foreign account')
    post dashboard_sales_records_path(kind: 'opportunity', site_id: @site.id), params: {record: {name: 'Cross tenant', account_id: foreign.id, close_on: Date.current}}, headers: headers.merge('X-CSRF-Token' => csrf)
    assert_response :unprocessable_entity
    assert_equal 0, LightekSales::Opportunity.count
    row = deal
    patch record_path('opportunity', row), params: {record: {account_id: foreign.id, stage: 'unsupported', lock_version: row.lock_version}}, headers: headers.merge('X-CSRF-Token' => csrf)
    assert_response :unprocessable_entity
    refute_includes response.body, foreign.name
    assert_equal 'proposal', row.reload.stage
    assert_raises(ActiveRecord::RecordNotFound) { get dashboard_sales_path(site_id: @site.id, tab: 'routing'), headers: headers(@member) }
    account = row.account
    %w[-1 1.001 1e4 NaN].each do |amount|
      assert_raises(ArgumentError) { @workspace.save!('opportunity', {name: 'Invalid value', account_id: account.id, amount: amount, close_on: Date.current}) }
    end
    get dashboard_sales_path(site_id: @site.id, owner_id: @member.id), headers: headers
    assert_response :ok
    assert_raises(ActiveRecord::RecordNotFound) { get dashboard_sales_path(site_id: @site.id, owner_id: @other.id), headers: headers }
  end
  def test_native_views_all_tabs_errors_and_preview
    account = company
    contact = @workspace.save!('contact', {email: 'customer@example.test', sales_account_id: account.id, name: 'Jamie'})
    row = deal(account: account)
    lead(next_step: nil, follow_up_on: nil)
    %w[today leads pipeline accounts contacts routing].each do |tab|
      get dashboard_sales_path(site_id: @site.id, tab: tab), headers: headers
      assert_response :ok
      assert_includes response.body, 'Sales & CRM'
      assert_includes response.body, 'forecast'
      if ENV['SALES_PREVIEW_DIR'] && %w[today pipeline].include?(tab)
        FileUtils.mkdir_p(ENV['SALES_PREVIEW_DIR'])
        File.write(File.join(ENV['SALES_PREVIEW_DIR'], "#{tab}.html"), response.body)
      end
    end
    %w[lead account contact opportunity routing_rule].each do |kind|
      get new_dashboard_sales_record_path(kind: kind, site_id: @site.id), headers: headers
      assert_response :ok
    end
    [ ['contact', contact], ['account', account], ['opportunity', row] ].each do |kind, record|
      get record_path(kind, record), headers: headers
      assert_response :ok
      if ENV['SALES_PREVIEW_DIR'] && kind == 'opportunity'
        File.write(File.join(ENV['SALES_PREVIEW_DIR'], 'deal.html'), response.body)
      end
    end
    csrf = token
    post dashboard_sales_records_path(kind: 'opportunity', site_id: @site.id), params: {record: {name: '', account_id: account.id, close_on: Date.current}}, headers: headers.merge('X-CSRF-Token' => csrf)
    assert_response :unprocessable_entity
    assert_includes response.body, 'Review these fields'
    assert_equal 'commerce', LightekAgency::PackageFeatures.for_controller('dashboard/sales')
  end
  def record_path(kind, row) = dashboard_sales_record_path(kind: kind, id: row.id, site_id: @site.id)
end
