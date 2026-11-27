gem "minitest", "~>5.0"
require 'minitest/mock'
require_relative 'sales_intake_checks'
require ROOT.join('db/migrate/20261113160000_create_lightek_people_and_payroll')
CreateLightekPeopleAndPayroll.new.migrate(:up)
ActiveRecord::Schema.define do
  add_column :users, :agency_id, :bigint
  add_column :users, :upstream_share_bps, :integer, default: 0
  add_column :users, :api_token, :string
  add_column :lightek_people_employments, :directory_admin, :boolean, default: false
  add_column :lightek_people_employments, :directory_principal, :string
  add_column :lightek_people_employments, :accounting_access, :string, default: 'none'
  add_column :lightek_people_employments, :compliance_access, :string, default: 'none'
  create_table(:sessions) { |t| t.references :user; t.references :identity_connection; t.timestamps }
  create_table(:lightek_identity_connections) do |t|
    t.references :employer
    %i[slug client_id issuer authorization_endpoint token_endpoint jwks_uri].each { |key| t.string key }
  end
  create_table(:gatekeeper_nodes) { |t| t.references :owner, polymorphic: true }
  create_table(:lightek_identity_resource_grants) { |t| t.references :employer; t.references :subject, polymorphic: true; t.references :resource, polymorphic: true; t.string :permission }
end
User.reset_column_information
require ROOT.join('app/models/concerns/account_hierarchy')
class User
  belongs_to :agency, class_name: 'User', optional: true
  has_many :agency_clients, class_name: 'User', foreign_key: :agency_id
  has_many :sessions
  has_secure_token :api_token
  include AccountHierarchy
end
require ROOT.join('app/models/session')
class GatekeeperNode < ApplicationRecord
  belongs_to :owner, polymorphic: true
end
class DirectorySyncJob < ApplicationJob
  queue_as :default
end
module LightekIdentity
  module DirectoryPolicy
    def self.changed!(*) = nil
  end
  module SensitiveSession
    # Host MFA/session freshness is a boundary fixture, not tested here.
    def require_sensitive_session! = nil
  end
end
require ROOT.join('app/models/lightek_identity/resource_grant')
require ROOT.join('app/models/lightek_identity/connection')
require ROOT.join('app/services/lightek_identity/session_containment')
require ROOT.join('app/models/lightek_people/department')
require ROOT.join('app/models/lightek_people/employment')
require ROOT.join('app/services/lightek_people/access')
require ROOT.join('app/services/lightek_people/lifecycle')
require ROOT.join('db/migrate/20261112190000_create_lightek_connect')
CreateLightekConnect.new.migrate(:up)
require ROOT.join('app/models/lightek_connect/event')
require ROOT.join('app/models/lightek_connect/connection')
module Gatekeeper
  module Hosting
    class Access
      class Denied < StandardError; end
    end
  end
end
class ApplicationController < Dashboard::SettingsHomeController
  def self.allow_unauthenticated_access(*) = skip_before_action(:require_settings_operator!)
  def self.skip_authorization_check(*) = nil
end
require ROOT.join('app/controllers/sales_quotes_controller')
require ROOT.join('app/services/dymond_bank/workforce_payouts')
module LightekPeople
  module Payroll
    class Invalid < StandardError; end
  end
  module StarterDepartments
    def self.ensure!(*) = nil
  end
end
require ROOT.join('app/models/lightek_people/audit_event')
require ROOT.join('app/controllers/dashboard/people_controller')
require ROOT.join('app/controllers/dashboard/lifecycle_controller')
[SalesQuotesController, Dashboard::LifecycleController, Dashboard::SalesQuotesController].each { |klass| klass.prepend_view_path ROOT.join('app/views'); klass.layout false }
SalesHarness.routes.draw do
  eval(ROOT.join('config/routes/campaign_performance.rb').read, binding)
  eval(ROOT.join('config/routes/website_audits.rb').read, binding)
  eval(ROOT.join('config/routes/publication_calendar.rb').read, binding)
  eval(ROOT.join('config/routes/campaign_content.rb').read, binding)
  eval(ROOT.join('config/routes/growth.rb').read, binding)
  eval(ROOT.join('config/routes/lifecycle.rb').read, binding)
  eval(ROOT.join('config/routes/sales_quotes.rb').read, binding)
  eval(ROOT.join('config/routes/sales.rb').read, binding)
  post '/people/employments', to: 'dashboard/people#employment', as: :dashboard_people_employments
  get '/people', to: 'dashboard/lifecycle#index', as: :dashboard_people
  get '/csrf', to: 'dashboard/settings_home#csrf'
  get '/orders', to: 'dashboard/sales#index', as: :dashboard_commerce_orders
  get '/customers/history', to: 'dashboard/sales#index', as: :history_dashboard_customers
  %w[business_hub website_designs media_studio marketing_campaigns commerce customers pwa].each do |name|
    get "/workspace/#{name}", to: 'dashboard/sales#index', as: "dashboard_#{name}"
  end
end
SalesCrmChecks.prepend(Module.new do
  def setup
    [LightekPeople::AuditEvent, LightekPeople::LifecycleCase, LightekIdentity::ResourceGrant, LightekPeople::Employment, LightekPeople::Department,
     LightekConnect::Event, LightekConnect::Connection, Session, LightekIdentity::Connection, GatekeeperNode].each(&:delete_all)
    super
  end
end)
class LifecycleQuoteChecks < SalesCrmChecks
  def self.runnable_methods = super.grep(/test_workflow_/)
  def employment(worker = @member, **values)
    LightekPeople::Employment.create!({employer: @owner, worker: worker, title: 'Sales specialist', starts_on: Date.current - 10, active: true, lifecycle_activation: true}.merge(values))
  end
  def workflow(actor = @owner) = LightekPeople::Lifecycle.new(actor: actor, employer: @owner)

  def test_workflow_session_containment_only_revokes_sessions_for_the_selected_employer
    member = employment
    attributes = {client_id: 'test-client', issuer: 'https://id.example.test', authorization_endpoint: 'https://id.example.test/auth',
      token_endpoint: 'https://id.example.test/token', jwks_uri: 'https://id.example.test/keys'}
    own = LightekIdentity::Connection.create!(**attributes, employer: @owner, slug: 'company-identity')
    foreign = LightekIdentity::Connection.create!(**attributes, employer: @member, slug: 'other-identity')
    targeted = @member.sessions.create!(identity_connection_id: own.id)
    retained = @member.sessions.create!(identity_connection_id: foreign.id)
    local = @member.sessions.create!

    service = LightekIdentity::SessionContainment
    assert_raises(LightekPeople::Access::Denied) { service.revoke!(actor: @member, employer: @owner, membership_id: member.id) }
    assert_equal 1, service.revoke!(actor: @owner, employer: @owner, membership_id: member.id)
    refute Session.exists?(targeted.id)
    assert Session.exists?(retained.id)
    assert Session.exists?(local.id)
    assert LightekPeople::AuditEvent.exists?(employer: @owner, actor: @owner,
      action: 'directory_sso_sessions_revoked', record_id: member.id)
  end
  def offer(**values)
    LightekCommerce::Product.create!({site: @site, name: 'Managed website', slug: SecureRandom.hex(4), price_cents: 25000, product_type: 'service', billing_interval: 'one_time', published: true}.merge(values))
  end
  def draft(product: offer, opportunity: deal)
    LightekSales::Quotes.new(actor: @owner, site: @site).draft!(opportunity_id: opportunity.id, values: {title: 'Website package', customer_email: 'buyer@example.test', terms: 'Delivery after payment and kickoff.', expires_on: Date.current + 14}, quantities: {product.id => 1})
  end
  def issued(**values)
    quote = draft(**values)
    LightekSales::Quotes.new(actor: @owner, site: @site).issue!(id: quote.id, version: quote.lock_version)
  end
  def test_workflow_nevaeh_issues_only_the_reviewed_quote_revision
    quote = draft
    command = NevaehOs::PlatformActions.command('sales.quote.issue',
      {'site_id'=>@site.id, 'quote_id'=>quote.id, 'lock_version'=>quote.lock_version})
    assert_raises(ActiveRecord::RecordNotFound) do
      NevaehOs::PlatformActions.perform!(actor: @other, command: command, action_id: 1)
    end
    quote.update!(title: 'New reviewed title')
    assert_raises(ActiveRecord::StaleObjectError) do
      NevaehOs::PlatformActions.perform!(actor: @owner, command: command, action_id: 2)
    end
    command['payload']['lock_version'] = quote.reload.lock_version
    receipt = NevaehOs::PlatformActions.perform!(actor: @owner, command: command, action_id: 3)
    assert_equal 'issued', receipt.fetch('quote_status')
    assert_equal 'issued', quote.reload.status
    assert_nil quote.order_id
  end

  def finish_steps(record, service = workflow)
    LightekPeople::Lifecycle::STEPS.fetch(record.kind).each_key do |key|
      service.attest!(id: record.id, step: key, evidence: "Reviewed #{key}", version: record.reload.lock_version)
    end
  end
  def test_workflow_employee_offboarding_revokes_grants_sessions_tokens_and_hands_off_open_work
    person = employment
    node = GatekeeperNode.create!(owner: @owner)
    LightekIdentity::ResourceGrant.create!(employer: @owner, subject: person, resource: node, permission: 'read')
    @member.sessions.create!
    old_token = @member.reload.api_token
    cached_workspace = LightekSales::Workspace.new(actor: @member, site: @site)
    prospect = lead(owner_id: @member.id)
    task = LightekSales::Tasks.new(actor: @owner, site: @site).create!(kind: 'lead', id: prospect.id, values: {owner_id: @member.id, title: 'Call buyer', due_at: Time.current})
    record = workflow.start!(kind: 'employee_offboarding', subject: person)
    workflow.revoke!(id: record.id, version: 0)
    assert_equal 'access_revoked', record.reload.status
    assert_raises(ActiveRecord::RecordInvalid) { LightekPeople::Employment.find(person.id).update!(active: true) }
    person.reload
    refute person.reload.active?
    assert_equal Date.current, person.ends_on
    assert person.worked_during?(Date.current - 10, Date.current)
    assert_equal 0, LightekIdentity::ResourceGrant.count
    assert_raises(ActiveRecord::RecordNotFound) { cached_workspace.save!('lead', {name: 'Stale worker', email: 'stale@example.test', company: 'Stale'}) }
    assert_equal 0, @member.sessions.count
    refute_equal old_token, @member.reload.api_token
    assert @member.access_suspended_at
    assert_equal @owner.id, prospect.reload.owner_id
    assert_equal @owner.id, task.reload.owner_id
    assert_equal 0, LightekAgency::SiteMembership.where(user: @member, site: @site).count
    assert_raises(ActiveRecord::RecordNotFound) { LightekSales::Workspace.new(actor: @member, site: @site) }
    assert_equal record.id, workflow.revoke!(id: record.id, version: 0).id
    assert_raises(ArgumentError) { workflow.complete!(id: record.id, version: record.lock_version) }
    finish_steps(record)
    workflow.complete!(id: record.id, version: record.reload.lock_version)
    assert_equal 'completed', record.reload.status
    assert_raises(ActiveRecord::RecordInvalid) { LightekPeople::Employment.find(person.id).update!(active: true) }
  end
  def test_workflow_employee_with_other_employer_retains_other_membership
    person = employment
    other = LightekPeople::Employment.create!(employer: @other, worker: @member, title: 'Other work', lifecycle_activation: true, starts_on: Date.current - 1)
    LightekAgency::SiteMembership.create!(site: @foreign_site, user: @member, granted_by: @other, role: 'manager')
    record = workflow.start!(kind: 'employee_offboarding', subject: person)
    workflow.revoke!(id: record.id, version: 0)
    assert other.reload.active?
    assert_nil @member.reload.access_suspended_at
    assert LightekAgency::SiteMembership.exists?(site: @foreign_site, user: @member)
  end
  def test_workflow_hr_cannot_revoke_it_access_and_it_activates_ordinary_membership_after_evidence
    hr = employment(@designer, people_admin: true)
    it = employment(@member, directory_admin: true)
    candidate = User.create!(role: 'employee', email_address: 'new@example.test')
    person = employment(candidate, active: false)
    record = workflow(@designer).start!(kind: 'employee_onboarding', subject: person)
    assert_raises(LightekPeople::Access::Denied) { workflow(@designer).attest!(id: record.id, step: 'equipment', evidence: 'HR cannot approve IT', version: 0) }
    workflow(@designer).attest!(id: record.id, step: 'identity', evidence: 'Identity verified', version: record.reload.lock_version)
    workflow(@designer).attest!(id: record.id, step: 'orientation', evidence: 'Training complete', version: record.reload.lock_version)
    workflow(@member).attest!(id: record.id, step: 'equipment', evidence: 'Least privilege reviewed', version: record.reload.lock_version)
    workflow(@member).complete!(id: record.id, version: record.reload.lock_version)
    assert person.reload.active?
    offboard = workflow(@designer).start!(kind: 'employee_offboarding', subject: person)
    assert_raises(LightekPeople::Access::Denied) { workflow(@designer).revoke!(id: offboard.id, version: 0) }
  end
  def test_workflow_agency_onboarding_and_offboarding_preserve_clients_and_revoke_connect
    @owner.update!(role: 'super_admin')
    agency = User.create!(role: 'white_label', email_address: 'agency@example.test', agency: @owner)
    client = User.create!(role: 'client', email_address: 'client@example.test', agency: agency)
    record = workflow.start!(kind: 'agency_onboarding', subject: agency)
    refute LightekPeople::LifecycleAccess.agency_ready?(agency)
    assert_equal [agency.id], agency.managed_account_ids
    finish_steps(record)
    workflow.complete!(id: record.id, version: record.reload.lock_version)
    assert LightekPeople::LifecycleAccess.agency_ready?(agency)
    connection, = LightekConnect::Connection.issue!(user: agency, platform: 'wordpress', label: 'Client tool')
    staff_user = User.create!(role: 'employee', email_address: 'agency-staff@example.test')
    staff = LightekPeople::Employment.create!(employer: agency, worker: staff_user, title: 'Agency support', lifecycle_activation: true, starts_on: Date.current - 1)
    record = workflow.start!(kind: 'agency_offboarding', subject: agency)
    workflow.revoke!(id: record.id, version: 0)
    assert agency.reload.access_suspended_at
    refute staff.reload.active?
    assert staff_user.reload.access_suspended_at
    assert connection.reload.revoked_at
    assert_equal agency.id, client.reload.agency_id
    assert_nil client.access_suspended_at
    assert_empty agency.managed_account_ids
    assert LightekSettings::WebsiteIdentity.sites_for(client)
  end
  def test_workflow_foreign_membership_and_stale_checklist_are_denied
    foreign = LightekPeople::Employment.create!(employer: @other, worker: @member, title: 'Other', lifecycle_activation: true, starts_on: Date.current)
    assert_raises(ActiveRecord::RecordInvalid) { workflow.start!(kind: 'employee_offboarding', subject: foreign) }
    person = employment
    record = workflow.start!(kind: 'employee_offboarding', subject: person)
    assert_raises(ActiveRecord::StaleObjectError) { workflow.attest!(id: record.id, step: 'handoff', evidence: 'Old draft', version: 9) }
  end
  def test_workflow_quote_acceptance_creates_one_pending_order_and_real_catalog_snapshot
    quote = issued
    assert_raises(ActiveRecord::RecordInvalid) { quote.update!(terms: 'Changed after issuing') }
    quote.reload
    2.times { LightekSales::Quotes.accept!(quote: quote, name: 'Buyer', reference: 'Email approval', actor: @owner) }
    assert_equal 1, LightekCommerce::Order.count
    assert_equal 'pending_payment', quote.reload.order.status
    assert_nil quote.order.paid_at
    assert_equal 25000, quote.order.total_cents
    assert_equal 'closed_won', quote.opportunity.reload.stage
    assert_equal @owner, quote.accepted_by
    assert_equal 'staff', quote.acceptance_channel
    assert_equal 'service', quote.order.items.first.purchase_snapshot['product_type']
  end
  def test_workflow_quote_price_changes_expiration_and_revisions_do_not_charge_or_create_orders
    product = offer
    quote = issued(product: product)
    product.update!(price_cents: 30000)
    assert_raises(ArgumentError) { LightekSales::Quotes.accept!(quote: quote, name: 'Buyer', reference: 'portal') }
    assert_equal 0, LightekCommerce::Order.count
    service = LightekSales::Quotes.new(actor: @owner, site: @site)
    revision = service.draft!(opportunity_id: quote.opportunity_id, previous_id: quote.id, values: {title: 'Updated quote', customer_email: quote.customer_email, expires_on: Date.current + 7}, quantities: {product.id => 1})
    service.issue!(id: revision.id, version: revision.lock_version)
    assert_equal 'superseded', quote.reload.status
    assert_equal 2, revision.revision
    assert_equal 30000, revision.total_cents
    assert_raises(ArgumentError) { LightekSales::Quotes.accept!(quote: quote, name: 'Buyer', reference: 'old portal') }
    revision.reload.update_columns(expires_on: Date.current - 1)
    assert_raises(ArgumentError) { LightekSales::Quotes.accept!(quote: revision, name: 'Buyer', reference: 'expired') }
  end
  def test_workflow_quote_foreign_products_and_unsupported_currency_are_rejected
    product = offer(site: @foreign_site)
    assert_raises(ArgumentError) { draft(product: product) }
    opportunity = deal(account: LightekSales::Account.find_by(site: @site) || company, currency: 'EUR')
    assert_raises(ArgumentError) { draft(product: offer, opportunity: opportunity) }
    assert_equal 0, LightekSales::Quote.count
  end
  def test_workflow_quote_portal_host_csrf_payment_handoff_and_verified_status
    quote = issued
    token_value = quote.signed_id(purpose: 'sales_quote', expires_in: 1.day)
    host! 'lightek.test'
    get public_sales_quote_path(token: token_value)
    assert_response :ok
    assert_includes response.body, 'Your quote'
    csrf = token
    post accept_public_sales_quote_path(token: token_value), params: {accepted: '1', accepted_name: 'Customer'}, headers: {'X-CSRF-Token' => csrf}
    assert_response :see_other
    assert_equal 'accepted', quote.reload.status
    assert_equal 'customer_portal', quote.acceptance_channel
    gateway = ->(**args) { assert_equal quote.order_id, args[:order].id; Struct.new(:url).new('https://checkout.stripe.com/test-only') }
    LightekCommerce::StripeCheckout.stub(:start!, gateway) do
      post checkout_public_sales_quote_path(token: token_value), headers: {'X-CSRF-Token' => csrf}
      assert_response :see_other
      assert_equal 'https://checkout.stripe.com/test-only', response.location
    end
    assert_nil quote.order.reload.paid_at
    host! 'foreign.test'
    get public_sales_quote_path(token: token_value)
    assert_response :not_found
  end
  def test_workflow_embedded_quote_checkout_retains_the_signed_host_and_order
    quote = issued
    LightekSales::Quotes.accept!(quote: quote, name: 'Buyer', reference: 'Acceptance', actor: @owner)
    token_value = quote.signed_id(purpose: 'sales_quote', expires_in: 1.day)
    host! 'lightek.test'
    csrf = token
    gateway = LightekCommerce::StripeCheckout
    checkout = OpenStruct.new(url: nil, client_secret: 'quote_fixture_secret')
    path = embedded_public_sales_quote_path(token: token_value)
    gateway.stub(:embedded_for?, true) do
      gateway.stub(:start!, ->(**args) {
        assert args[:embedded]
        assert_equal quote.order_id, args[:order].id
        checkout
      }) do
        post checkout_public_sales_quote_path(token: token_value), headers: {'X-CSRF-Token' => csrf}
        assert_redirected_to path
      end
    end
    gateway.stub(:resume!, ->(**args) {
      assert args[:embedded]
      assert_equal quote.order_id, args[:order].id
      checkout
    }) do
      gateway.stub(:embedded_publishable_key, 'pk_test_fixture') do
        get path
        assert_response :success
        assert_select '[data-embedded-checkout][data-checkout-secret="quote_fixture_secret"]'
        assert_equal 'private, no-store', response.headers['Cache-Control']
        host! 'foreign.test'
        get path
        assert_response :not_found
      end
    end
  end

  def test_workflow_canceled_onboarding_cannot_activate_and_can_be_replaced
    person = employment(active: false)
    record = workflow.start!(kind: 'employee_onboarding', subject: person)
    workflow.cancel!(id: record.id, version: record.lock_version)
    assert_equal 'canceled', record.reload.status
    assert_raises(ArgumentError) { workflow.complete!(id: record.id, version: record.lock_version) }
    refute person.reload.active?
    replacement = workflow.start!(kind: 'employee_onboarding', subject: person)
    refute_equal record.id, replacement.id
    finish_steps(replacement)
    workflow.complete!(id: replacement.id, version: replacement.reload.lock_version)
    assert person.reload.active?
  end
  def test_workflow_portal_rejects_missing_csrf_and_does_not_accept_unissued_quotes
    quote = draft
    host! 'lightek.test'
    token_value = quote.signed_id(purpose: 'sales_quote', expires_in: 1.day)
    csrf = token
    post accept_public_sales_quote_path(token: token_value), params: {accepted: '1', accepted_name: 'Customer'}, headers: {'X-CSRF-Token' => csrf}
    assert_response :unprocessable_entity
    assert_equal 0, LightekCommerce::Order.count
    assert_raises(ActionController::InvalidAuthenticityToken) do
      post accept_public_sales_quote_path(token: token_value), params: {accepted: '1', accepted_name: 'Customer'}
    end
  end
  def test_workflow_handoff_failure_cannot_restore_revoked_access_and_is_recoverable
    person = employment
    prospect = lead(owner_id: @member.id)
    prospect.update_columns(phone: 'x' * 1000)
    record = workflow.start!(kind: 'employee_offboarding', subject: person)
    workflow.revoke!(id: record.id, version: 0)
    assert_equal 'access_revoked', record.reload.status
    refute person.reload.active?
    assert @member.reload.access_suspended_at
    assert_equal @owner, record.revoked_by
    assert_equal 'needs_attention', record.receipt['handoff_state']
    LightekSales::Lead.find(prospect.id).update!(phone: nil, owner: @owner)
    workflow.revoke!(id: record.id, version: record.lock_version)
    assert_equal 'completed', record.reload.receipt['handoff_state']
  end
  def test_workflow_native_people_creation_stages_membership_and_opens_onboarding
    csrf = token
    post dashboard_people_employments_path(employer_id: @owner.id), params: {worker_email: @member.email_address, employment: {title: 'New hire', starts_on: Date.current, level: 'individual_contributor', worker_kind: 'employee', active: '1'}}, headers: headers.merge('X-CSRF-Token' => csrf)
    assert_response :see_other
    member = LightekPeople::Employment.find_by!(employer: @owner, worker: @member)
    refute member.active?
    assert LightekPeople::LifecycleCase.exists?(subject: member, kind: 'employee_onboarding', status: 'open')
  end
  def test_workflow_native_lifecycle_and_quote_views_render
    employment
    workflow.start!(kind: 'employee_offboarding', subject: LightekPeople::Employment.first)
    get dashboard_lifecycle_path(employer_id: @owner.id), headers: headers
    assert_response :ok
    assert_includes response.body, 'Revoke access &amp; hand off work'
    File.write(File.join(ENV['SALES_PREVIEW_DIR'], 'lifecycle.html'), response.body) if ENV['SALES_PREVIEW_DIR']
    quote = issued
    get dashboard_sales_quote_path(site_id: @site.id, id: quote.id), headers: headers
    assert_response :ok
    assert_includes response.body, 'Customer link'
    if ENV['SALES_PREVIEW_DIR']
      File.write(File.join(ENV['SALES_PREVIEW_DIR'], 'quote.html'), response.body)
    end
  end
end
