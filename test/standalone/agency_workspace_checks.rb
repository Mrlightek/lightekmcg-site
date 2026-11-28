# Real controller/view requests with an in-memory account graph. Payment and site
# authorization services are replaced only at their existing boundary.
gem 'minitest', '~> 5.25'
require 'minitest/autorun'
require 'active_record'
require 'action_controller/railtie'
require 'action_dispatch/testing/integration'
require 'tmpdir'
ROOT = Pathname.new(File.expand_path('../..', __dir__))
class AgencyWorkspaceHarness < Rails::Application
  config.root = Dir.mktmpdir('agency-workspace-')
  config.eager_load = false
  config.secret_key_base = 'agency-workspace-test-' * 8
  config.hosts.clear
  config.logger = Logger.new(File::NULL)
  config.action_dispatch.show_exceptions = :none
  config.action_controller.allow_forgery_protection = false
end
AgencyWorkspaceHarness.initialize!
ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Schema.define do
  create_table(:users) { |t| t.string :role; t.string :email_address; t.string :first_name; t.string :last_name; t.string :password; t.integer :agency_id; t.integer :upstream_share_bps, default: 0; t.boolean :password_setup_required, default: false }
  create_table(:agency_profiles) { |t| t.integer :user_id; t.string :brand_name }
  create_table(:sites) { |t| t.integer :tenant_id; t.string :name; t.string :host; t.json :manifest }
  create_table(:orders) { |t| t.integer :hosting_owner_id; t.string :customer_email; t.string :provisioning_state; t.timestamps }
  create_table(:gatekeeper_nodes) { |t| t.string :owner_type; t.integer :owner_id }
  create_table(:products) { |t| t.string :name; t.integer :price_cents; t.string :short_description }
  create_table(:hosting_packages) { |t| t.integer :product_id }
end
class User < ActiveRecord::Base
  belongs_to :agency, class_name: 'User', optional: true
  has_many :agency_clients, class_name: 'User', foreign_key: :agency_id
  validates :email_address, presence: true, uniqueness: true
  has_one :agency_profile
  def white_label? = role == 'white_label'
  def full_name = [first_name, last_name].compact.join(' ').presence || email_address
  def managed_account_ids = [id] + agency_clients.pluck(:id)
  def password_setup_invitation_error = nil
  def send_password_setup_invitation! = true
end
class AgencyProfile < ActiveRecord::Base; end
class Site < ActiveRecord::Base; end
class Order < ActiveRecord::Base; end
class GatekeeperNode < ActiveRecord::Base; end
class Product < ActiveRecord::Base; end
class HostingPackage < ActiveRecord::Base
  belongs_to :product
  scope :available, -> { all }
end
module LightekAgency
  module Access
    def self.sites_for(user) = user.role == 'super_admin' ? Site.all : Site.where(tenant_id: user.managed_account_ids)
  end
end
module LightekSettings
  module WebsiteIdentity
    def self.sites_for(user) = Site.where(tenant_id: user.id)
  end
end
module LightekCommerce
  module Installations
    def self.scope_for(user, operator: false) = operator ? Order.all : Order.where(customer_email: user.email_address)
    def self.summary(order) = {hostname: "client-#{order.hosting_owner_id}.example.test", state: order.provisioning_state}
  end
end
require ROOT.join('app/services/gatekeeper/hosting/access')
require ROOT.join('app/helpers/infrastructure_dashboard_helper')
class ApplicationController < ActionController::Base
  def current_user = User.find(request.headers.fetch('X-Test-User'))
  helper_method :current_user
  def self.rate_limit(**) = nil
end
module Current
  def self.session = Struct.new(:connect_delegation).new
end
module NevaehOnboarding
  module StandingAssignment
    def self.paid_trial(*) = nil
  end
end
module Dashboard; end
require ROOT.join('app/controllers/dashboard/agencies_controller')
require ROOT.join('app/controllers/dashboard/server_instances_controller')
[Dashboard::AgenciesController, Dashboard::ServerInstancesController].each do |controller|
  controller.layout false
  controller.prepend_view_path ROOT.join('app/views')
end
AgencyWorkspaceHarness.routes.draw do
  resources :dashboard_agencies, path: '/dashboard/agencies', controller: 'dashboard/agencies', only: %i[index create update] do
    member do
      post :create_client
      post :send_setup_invitation
      patch :update_terms
    end
  end
  get '/dashboard/servers', to: 'dashboard/server_instances#index', as: :dashboard_servers
  get '/dashboard/servers/hosting', to: 'dashboard/server_instances#hosting', as: :hosting_dashboard_servers
  get '/dashboard/agency-websites/:id', to: 'dashboard/agencies#index', as: :dashboard_agency_website
  get '/dashboard/business', to: 'dashboard/agencies#index', as: :dashboard_business_hub
  get '/dashboard/reseller-packages', to: 'dashboard/agencies#index', as: :dashboard_reseller_packages
  get '/dashboard/demos', to: 'dashboard/agencies#index', as: :dashboard_demos
  get '/dashboard/lifecycle', to: 'dashboard/agencies#index', as: :dashboard_lifecycle
  get '/installations/:id', to: 'dashboard/agencies#index', as: :installation
  post '/dashboard/hosting/purchase', to: 'dashboard/agencies#create', as: :dashboard_hosting_purchase
  get '/dashboard/applications/install', to: 'dashboard/agencies#index', as: :new_dashboard_application_launch
  get '/dashboard/infrastructure/catalog', to: 'dashboard/agencies#index', as: :dashboard_infrastructure_catalog
  get '/dashboard/hosting/packages', to: 'dashboard/agencies#index', as: :dashboard_hosting_packages
end
class AgencyWorkspaceChecks < ActionDispatch::IntegrationTest
  def app = AgencyWorkspaceHarness
  def setup
    [User, Site, Order, HostingPackage, Product].each(&:delete_all)
    @agency = User.create!(role: 'white_label', email_address: 'agency@example.test')
    @client = User.create!(role: 'client', agency: @agency, email_address: 'client@example.test', password_setup_required: true)
    @foreign = User.create!(role: 'white_label', email_address: 'foreign@example.test')
    @foreign_client = User.create!(role: 'client', agency: @foreign, email_address: 'private@example.test')
    @headers = {'X-Test-User' => @agency.id.to_s}
    host! 'example.test'
  end
  def test_client_creation_returns_to_selected_setup_and_not_another_agency
    post "/dashboard/agencies/#{@agency.id}/create_client", params: {client: {first_name: 'New', last_name: 'Client', email_address: 'new@example.test'}}, headers: @headers
    created = @agency.agency_clients.find_by!(email_address: 'new@example.test')
    assert_redirected_to "/dashboard/agencies?agency_id=#{@agency.id}&client_id=#{created.id}#client-setup"
    assert_equal 'client', created.role
    assert created.password_setup_required?
    assert_raises(ActiveRecord::RecordNotFound) do
      post "/dashboard/agencies/#{@foreign.id}/create_client", params: {client: {email_address: 'bad@example.test'}}, headers: @headers
    end
  end
  def test_real_view_leads_with_client_creation_and_preserves_selected_owner
    get '/dashboard/agencies', params: {agency_id: @agency.id, client_id: @client.id}, headers: @headers
    assert_response :success
    assert_equal 'private, no-store', response.headers['Cache-Control']
    assert_select 'input[name="client[email_address]"][type="email"]', count: 1
    assert_select "a[href='/dashboard/servers/hosting?hosting_owner_id=#{@client.id}']", text: 'Choose a hosting plan'
    assert_select 'details.agency-settings[open]', count: 0
    assert_select '#client-setup', count: 1
    refute_includes response.body, @foreign_client.email_address
    assert_select '#new-client, details.agency-settings' do |sections|
      assert_equal 'new-client', sections.first['id']
    end
  end
  def test_foreign_agency_and_client_selections_are_rejected
    [{agency_id: @foreign.id}, {agency_id: @agency.id, client_id: @foreign_client.id}].each do |params|
      assert_raises(ActiveRecord::RecordNotFound) { get '/dashboard/agencies', params: params, headers: @headers }
    end
    get '/dashboard/agencies', headers: {'X-Test-User' => @client.id.to_s}
    assert_response :forbidden
  end
  def test_setup_only_shows_selected_clients_authorized_sites_and_orders
    mine = Site.create!(tenant_id: @client.id, name: 'Client shop', host: 'shop.example.test')
    Site.create!(tenant_id: @foreign_client.id, name: 'Private shop', host: 'private.example.test')
    order = Order.create!(hosting_owner_id: @client.id, customer_email: @agency.email_address, provisioning_state: 'queued')
    Order.create!(hosting_owner_id: @foreign_client.id, customer_email: @agency.email_address, provisioning_state: 'ready')
    get '/dashboard/agencies', params: {agency_id: @agency.id, client_id: @client.id}, headers: @headers
    assert_response :success
    assert_select "a[href='/dashboard/business?site_id=#{mine.id}']", text: 'Open business workspace'
    assert_select "a[href='/installations/#{order.id}']", text: 'View installation'
    assert_select '#client-setup', text: /Queued/
    refute_includes response.body, 'Private shop'
    refute_includes response.body, "client-#{@foreign_client.id}.example.test"
  end
  def test_email_search_escapes_wildcards_and_keeps_agency_scope
    get '/dashboard/agencies', params: {agency_id: @agency.id, q: '%'}, headers: @headers
    assert_response :success
    assert_includes response.body, 'No clients match that email'
    get '/dashboard/agencies', params: {agency_id: @agency.id, q: 'CLIENT@'}, headers: @headers
    assert_select '.agency-site strong', text: @client.full_name
    refute_includes response.body, @foreign_client.email_address
  end
  def test_hosting_prefills_the_client_in_every_package_and_rejects_other_accounts
    HostingPackage.create!(product: Product.create!(name: 'Managed hosting', price_cents: 2500))
    get '/dashboard/servers/hosting', params: {hosting_owner_id: @client.id}, headers: @headers
    assert_response :success
    assert_select 'select[name="hosting_owner_id"] option[selected][value=?]', @client.id.to_s
    assert_select 'a', text: 'Back to client setup' do |links|
      assert_includes links.first['href'], "client_id=#{@client.id}"
    end
    assert_raises(ActiveRecord::RecordNotFound) do
      get '/dashboard/servers/hosting', params: {hosting_owner_id: @foreign_client.id}, headers: @headers
    end
  end
end
