# Actual controllers, settings persistence, Vault crypto and signature validation.
# Host authentication, commerce settlement and YouTube HTTP are boundaries.
ENV['DATABASE_URL'] = 'sqlite3::memory:'
require 'rails'
require 'active_record/railtie'
require 'action_controller/railtie'
require 'action_dispatch/testing/integration'
require 'minitest/autorun'
require 'minitest/mock'
require 'tmpdir'
require 'stripe'
require 'openssl'
require 'base64'
ROOT = File.expand_path('../..', __dir__)
class LaunchSetupTestApp < Rails::Application
  config.root = Dir.mktmpdir('pwa-launch-setup')
  config.secret_key_base = 'setup-tests-' * 15
  config.eager_load = false
  config.hosts.clear
  config.logger = Logger.new(File::NULL)
end
Rails.application.initialize!
ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Migration.verbose = false
class ApplicationRecord < ActiveRecord::Base; self.abstract_class = true; end
ActiveRecord::Schema.define do
  create_table(:users) { |t| t.string :role; t.string :email_address }
  create_table(:dymond_site_sites) { |t| t.references :tenant, polymorphic: true; t.string :host; t.json :manifest, default: {} }
  create_table(:lightek_pwa_platform_operators) { |t| t.integer :site_id; t.integer :operator_id }
end
class User < ApplicationRecord; end
module DymondSite
  class Site < ApplicationRecord
    self.table_name = 'dymond_site_sites'
    belongs_to :tenant, polymorphic: true
  end
end
require ROOT + '/db/migrate/20261117170000_create_pwa_launch_settings'
CreatePwaLaunchSettings.new.migrate(:up)
# Same Vault migration with SQLite's JSON and index syntax for this fixture.
path = ROOT + '/db/migrate/20260927111553_create_lightek_vault.rb'
eval(File.read(path).gsub('t.jsonb', 't.json').gsub(', using: :gin', ''), TOPLEVEL_BINDING, path)
CreateLightekVault.new.migrate(:up)
%w[app/models/lightek_pwa/platform_operator app/models/lightek_pwa/launch_settings app/models/lightek_vault/secret app/models/lightek_vault/audit_event
 app/services/lightek_vault/master_key app/services/lightek_vault/crypto app/services/lightek_vault/policy app/services/lightek_vault/service
 app/services/lightek_pwa/policy app/services/lightek_commerce/webhook_credentials app/services/lightek_pwa/youtube_api app/services/lightek_pwa/launch_setup].each { |p| require ROOT + '/' + p }
require ROOT + '/app/services/lightek_pwa/creator_support'
module LightekPwa
  %i[Plans MemberBackends BackendMigration ViewSettlement].each do |name|
    const_set(name, Class.new { const_set(:Unavailable, Class.new(StandardError)) })
  end
end
module LightekCommerce
  class StripeEvents
    class Rejected < StandardError; end
    def self.process!(event); end
  end
end
class ApplicationController < ActionController::Base
  def current_user = User.find_by(id: request.headers['X-Test-User'])
end
module DymondDash
  class ApplicationController < ::ApplicationController; end
end
module Dashboard; end
require ROOT + '/app/controllers/dashboard/pwa_revenue_controller'
require ROOT + '/app/controllers/commerce_stripe_webhooks_controller'
class SetupCsrfController < ApplicationController
  protect_from_forgery with: :exception
  def show = render(json: {csrf_token: form_authenticity_token})
end
Rails.application.routes.draw do
  get '/csrf', to: 'setup_csrf#show'
  get '/dashboard/pwa/revenue', to: 'setup_csrf#show', as: :dashboard_pwa_revenue
  get '/dashboard/vault', to: 'setup_csrf#show', as: :dashboard_vault
  post '/dashboard/pwa/revenue/launch-settings', to: 'dashboard/pwa_revenue#configure_launch', as: :configure_launch_dashboard_pwa_revenue
  post '/dashboard/pwa/revenue/payment-callbacks', to: 'dashboard/pwa_revenue#configure_webhook', as: :configure_webhook_dashboard_pwa_revenue
  post '/dashboard/pwa/revenue/verify-youtube', to: 'dashboard/pwa_revenue#verify_youtube', as: :verify_youtube_dashboard_pwa_revenue
  post '/commerce/stripe/webhook', to: 'commerce_stripe_webhooks#create', as: :commerce_stripe_webhook
end
ENV['LIGHTEK_VAULT_MASTER_KEY'] = Base64.strict_encode64(OpenSSL::Random.random_bytes(32))

class PwaLaunchSetupTest < Minitest::Test
  CHANNEL = 'UC' + 'a' * 22
  SIGNING = 'whsec_' + 'fixture' * 5
  def setup
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    @old_env = (LightekPwa::LaunchSettings::ENV_KEYS.values + ['LIGHTEK_COMMERCE_STRIPE_WEBHOOK_SECRET']).to_h { |key| [key, ENV.delete(key)] }
    @admin = User.create!(role: 'super_admin', email_address: 'operator@example.test')
    @owner = User.create!(role: 'client', email_address: 'owner@example.test')
    @site = DymondSite::Site.create!(host: 'central.example.test', tenant: @owner)
    @client = ActionDispatch::Integration::Session.new(Rails.application)
    @client.host! @site.host
  end
  def teardown
    @old_env.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
    ActiveRecord::Base.connection.rollback_transaction
  end
  def post(action, params, actor: @admin, csrf: true)
    headers = {'X-Test-User'=>actor&.id.to_s}
    if csrf
      @client.get '/csrf', headers: headers
      headers['X-CSRF-Token'] = JSON.parse(@client.response.body).fetch('csrf_token')
    end
    @client.post '/dashboard/pwa/revenue/' + action, params: params.merge(site_id: @site.id), headers: headers
    @client.response
  end
  def save(attributes = {}, actor: @admin, csrf: true, **fields)
    post('launch-settings', {launch_settings: attributes.merge(fields)}, actor: actor, csrf: csrf)
  end
  def credential
    LightekVault::Service.store!(name: '<Channel>', slug: 'central-youtube', payload: {'client_id'=>'fixture-client','client_secret'=>'fixture-secret','refresh_token'=>'fixture-refresh'},
      access_policy: {'consumers'=>['LightekPwa::YoutubeApi'],'purposes'=>['youtube_publishing']})
  end
  def select_channel
    credential
    save('youtube_channel_id'=>CHANNEL, 'youtube_credential_slug'=>'central-youtube')
    assert_equal 302, @client.response.status
  end
  def response(data)
    Net::HTTPOK.new('1.1', '200', 'OK').tap { |r| r.instance_variable_set(:@read, true); r.body = JSON.generate(data) }
  end
  def youtube(channel = CHANNEL)
    calls = []
    http = Object.new
    http.define_singleton_method(:request) do |request|
      calls << request
      data = request.path == '/token' ? {'access_token'=>'fixture-access'} : {'items'=>[{'id'=>channel}]}
      Net::HTTPOK.new('1.1','200','OK').tap { |r| r.instance_variable_set(:@read,true); r.body = JSON.generate(data) }
    end
    Net::HTTP.stub(:start, ->(*_, **_, &block) { block.call(http) }) { yield calls }
  end
  def test_environment_fallback_and_saved_false_are_consistent_across_reads
    ENV['LIGHTEK_CREATOR_SUPPORT_ENABLED'] = 'true'
    assert LightekPwa::LaunchSettings.enabled?('creator_support_enabled')
    assert_equal 302, save('creator_support_enabled'=>'0').status
    refute LightekPwa::LaunchSettings.enabled?('creator_support_enabled')
    refute LightekPwa::CreatorSupport.enabled?(@site)
    assert_equal @admin.id, LightekPwa::LaunchSettings.find(1).updated_by_id
    assert_equal @owner, @site.reload.tenant
  end
  def test_configuration_and_secret_writes_require_admin_and_csrf
    assert_equal 403, save({'member_mail_enabled'=>'1'}, actor: @owner).status
    assert_equal 403, save({'member_mail_enabled'=>'1'}, actor: nil).status
    assert_equal 422, save({'member_mail_enabled'=>'1'}, csrf: false).status
    assert_equal 403, post('payment-callbacks', {signing_secret: SIGNING}, actor: @owner).status
    assert_equal 422, post('payment-callbacks', {signing_secret: SIGNING}, csrf: false).status
    assert_equal 403, post('verify-youtube', {}, actor: @owner).status
    assert_equal 422, post('verify-youtube', {}, csrf: false).status
    assert_empty LightekPwa::LaunchSettings.all
    assert_empty LightekVault::Secret.all
  end
  def test_payment_secret_is_encrypted_not_returned_and_disabled_secret_fails_closed
    ENV['LIGHTEK_COMMERCE_STRIPE_WEBHOOK_SECRET'] = 'whsec_legacy_fixture_value'
    # Preserve the older dedicated endpoint for existing installations only.
    LightekCommerce::WebhookCredentials.store!(actor: @admin, value: SIGNING)
    secret = LightekVault::Secret.find_by!(slug: LightekCommerce::WebhookCredentials::SLUG)
    refute_includes secret.attributes.to_json, SIGNING
    assert_equal SIGNING, LightekCommerce::WebhookCredentials.secret
    assert LightekCommerce::WebhookCredentials.configured?
    assert LightekVault::AuditEvent.where(secret: secret, action: 'created', requested_by: @admin.email_address).exists?
    secret.update!(status: 'disabled')
    refute LightekCommerce::WebhookCredentials.configured?
    assert_raises(LightekCommerce::WebhookCredentials::Unavailable) { LightekCommerce::WebhookCredentials.secret }
  end
  def test_real_signed_callback_is_accepted_and_tampered_body_rejected
    LightekCommerce::WebhookCredentials.store!(actor: @admin, value: SIGNING)
    body = JSON.generate(id: 'evt_fixture', object: 'event', type: 'test.fixture', data: {object: {id: 'fixture'}})
    timestamp = Time.now.to_i
    signature = OpenSSL::HMAC.hexdigest('SHA256', SIGNING, "#{timestamp}.#{body}")
    headers = {'Stripe-Signature'=>"t=#{timestamp},v1=#{signature}", 'Content-Type'=>'application/json'}
    @client.post '/commerce/stripe/webhook', params: body, headers: headers
    assert_equal 200, @client.response.status, @client.response.body
    @client.post '/commerce/stripe/webhook', params: body + ' ', headers: headers
    assert_equal 400, @client.response.status
  end
  def test_retired_product_setup_does_not_create_a_duplicate_payment_secret
    assert_equal 302, post('payment-callbacks', {signing_secret: SIGNING}).status
    assert_empty LightekVault::Secret.all
    refute_includes @client.response.body, SIGNING
  end
  def test_uploads_cannot_open_before_verified_channel_and_changed_selection_invalidates_receipt
    select_channel
    save('youtube_uploads_enabled'=>'1')
    refute LightekPwa::LaunchSettings.enabled?('youtube_uploads_enabled')
    youtube do |calls|
      assert_equal 302, post('verify-youtube', {}).status
      assert_equal ['oauth2.googleapis.com', 'www.googleapis.com'], calls.map { |req| req.uri.host }
      assert_equal 'Bearer fixture-access', calls.last['Authorization']
    end
    save('youtube_uploads_enabled'=>'1')
    assert LightekPwa::LaunchSettings.enabled?('youtube_uploads_enabled')
    save('youtube_channel_id'=>'UC'+'b'*22)
    assert_equal CHANNEL, LightekPwa::LaunchSettings.value('youtube_channel_id')
    save('youtube_channel_id'=>'UC'+'b'*22, 'youtube_uploads_enabled'=>'0')
    assert_equal 'UC'+'b'*22, LightekPwa::LaunchSettings.value('youtube_channel_id')
    save('youtube_uploads_enabled'=>'1')
    refute LightekPwa::LaunchSettings.enabled?('youtube_uploads_enabled')
  end
  def test_wrong_authorized_channel_never_records_verification
    select_channel
    youtube('UC'+'b'*22) { post('verify-youtube', {}) }
    assert_equal 302, @client.response.status
    assert_nil LightekPwa::LaunchSettings.find(1).settings['youtube_verification']
    refute LightekPwa::LaunchSettings.enabled?('youtube_uploads_enabled')
  end
  def test_replaced_or_revoked_credential_requires_a_fresh_channel_check
    select_channel
    youtube { post('verify-youtube', {}) }
    original = LightekPwa::LaunchSettings.find(1).settings.fetch('youtube_verification')
    secret = LightekVault::Secret.find_by!(slug: 'central-youtube')
    secret.update!(last_rotated_at: Time.current)
    save('youtube_uploads_enabled'=>'1')
    refute LightekPwa::LaunchSettings.enabled?('youtube_uploads_enabled')
    assert_equal original, LightekPwa::LaunchSettings.find(1).settings['youtube_verification']
    youtube { post('verify-youtube', {}) }
    save('youtube_uploads_enabled'=>'1')
    assert LightekPwa::LaunchSettings.enabled?('youtube_uploads_enabled')
    save('youtube_uploads_enabled'=>'0')
    secret.update!(status: 'disabled')
    save('youtube_uploads_enabled'=>'1')
    refute LightekPwa::LaunchSettings.enabled?('youtube_uploads_enabled')
  end
  def test_wrong_vault_purpose_cannot_be_verified
    select_channel
    secret = LightekVault::Secret.find_by!(slug: 'central-youtube')
    secret.update!(access_policy: {'consumers'=>['AnotherConsumer'], 'purposes'=>['another_purpose']})
    post('verify-youtube', {})
    assert_equal 302, @client.response.status
    assert_nil LightekPwa::LaunchSettings.find(1).settings['youtube_verification']
  end
  def test_invalid_selections_and_private_manifest_do_not_change_launch_settings
    save('youtube_channel_id'=>'https://evil.test')
    assert_empty LightekPwa::LaunchSettings.all
    @site.update!(manifest: {'launch_settings'=>{'creator_payouts_enabled'=>true}})
    refute LightekPwa::LaunchSettings.enabled?('creator_payouts_enabled')
    assert_raises(ArgumentError) { LightekPwa::LaunchSetup.update!(site: @site, actor: @admin, attributes: {'secret'=>'private'}) }
  end
  def test_setup_view_uses_shared_bank_configuration_without_duplicate_secret_form
    select_channel
    view = ActionView::Base.with_empty_template_cache.with_view_paths(ROOT + '/app/views')
    view.extend(Rails.application.routes.url_helpers)
    view.define_singleton_method(:url_options) { {host: 'central.example.test', protocol: 'https'} }
    view.define_singleton_method(:optimize_routes_generation?) { false }
    view.define_singleton_method(:protect_against_forgery?) { false }
    view.assign(site: @site, launch_settings: LightekPwa::LaunchSettings.snapshot, youtube_credentials: [LightekVault::Secret.find_by!(slug:'central-youtube')], youtube_verification: {}, launch_readiness: {configuration: {payment_webhook: true}})
    html = view.render(partial: 'dashboard/pwa_revenue/launch_setup')
    assert_includes html, '/billing/webhooks/stripe'
    assert_includes html, 'DymondBank::StripeCredentials'
    assert_includes html, 'No separate PWA or Commerce credential is required'
    assert_includes html, '<strong>Configured</strong>'
    refute_includes html, 'name="signing_secret"'
    refute_includes html, '/commerce/stripe/webhook'
    assert_includes html, '&lt;Channel&gt;'
    assert_includes html, 'Verify channel authorization'
    assert_includes html, 'customer.subscription.created'
  end
end
