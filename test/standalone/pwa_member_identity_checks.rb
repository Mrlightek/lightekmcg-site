# Actual member sign-in controller and staff MFA rule. Signed central transport
# and primary-session creation are boundaries; identities persist in SQLite.
require_relative 'pwa_member_backend_checks'
ActiveRecord::Schema.define do
  create_table(:lightek_identity_factors) { |t| t.integer :user_id; t.datetime :enabled_at }
end
require 'base64'
require File.join(ROOT, 'app/services/lightek_settings/site_domain')
bootstrap = File.read(File.join(ROOT, 'script/lightek/website_deploy.sh')).match(/'payload\/app\/services\/lightek_website\/bootstrap.rb': '([^']+)'/)[1]
eval(Base64.strict_decode64(bootstrap), TOPLEVEL_BINDING, 'packaged/lightek_website/bootstrap.rb')
class User
  attr_accessor :last_name, :password_setup_required, :password, :password_confirmation, :skip_password_setup_invitation
  def password_setup_required? = !!password_setup_required
end
module LightekPeople
  class Employment
    def self.active = self
    def self.where(**) = self
    def self.exists? = false
    def self.pluck(*) = []
  end
end
module LightekIdentity
  class OrganizationPolicy
    class << self; attr_accessor :required; end
    def self.where(**) = self
    def self.exists? = required == true
  end
end
require File.join(ROOT, 'app/services/lightek_identity/mfa')
require File.join(ROOT, 'app/models/lightek_identity/factor')
require File.join(ROOT, 'app/controllers/pwa_member_sessions_controller')
require File.join(ROOT, 'app/controllers/identity_onboarding_controller')
class Current < ActiveSupport::CurrentAttributes
  attribute :session
end unless defined?(Current)
class MemberOnboardingProbeController < IdentityOnboardingController
  def resume_session
    Current.session = Struct.new(:connect_delegation, :user, :mfa_verified_at) do
      def mfa_enrollment_only? = false
    end.new({}, current_user, nil) if current_user
  end
end
class MemberIdentityProbeController < PwaMemberSessionsController
  # Keep the production authentication/MFA call boundary observable without
  # issuing a host session or replacing the actual role/MFA decisions.
  def complete_primary_authentication_for(user)
    render json: {role: user.role, mfa_required: LightekIdentity::Mfa.required?(user)}
  end
end
Rails.application.routes.append do
  get '/test/member-sign-in', to: 'member_identity_probe#create'
  get '/test/member-onboarding', to: 'member_onboarding_probe#show'
end
Rails.application.reload_routes!
class PwaMemberIdentityChecks < PwaMemberBackendTest
  PwaMemberBackendTest.instance_methods(false).grep(/^test_/).each { |name| undef_method(name) }
  def setup
    super
    Rails.cache.clear # Each identity case starts with its own rate-limit window.
    @owner.update!(role: 'admin', email_address: 'member@example.test')
    @config = {'key'=>backend.public_key, 'mode'=>'shared'}
    @remote.update!(manifest: {'pwa_member'=>@config})
    @data = {'backend_key'=>backend.public_key, 'hostname'=>@remote.host, 'email'=>@owner.email_address, 'account_role'=>'client'}
    LightekIdentity::OrganizationPolicy.required = false
    @browser = ActionDispatch::Integration::Session.new(Rails.application)
    @browser.host! @remote.host
  end
  def sign_in
    transport = Object.new
    data = @data
    transport.define_singleton_method(:request) { |*args, **kw| data }
    LightekReservations::Federation::Client.stub(:new, transport) do
      @browser.get '/test/member-sign-in', params: {ticket: 'a'*64, account_role: 'client'}
    end
  end
  def test_verified_free_member_uses_client_role_before_authentication
    sign_in
    assert_equal 200, @browser.response.status
    assert_equal 'client', @owner.reload.role
    assert_equal({'role'=>'client','mfa_required'=>false}, JSON.parse(@browser.response.body))
  end
  def test_organization_mfa_policy_still_applies_to_the_client
    LightekIdentity::OrganizationPolicy.required = true
    sign_in
    assert_equal true, JSON.parse(@browser.response.body)['mfa_required']
  end
  def test_existing_authenticator_is_preserved_for_the_member
    factor = LightekIdentity::Factor.create!(user: @owner, enabled_at: Time.current)
    sign_in
    assert_equal 'client', @owner.reload.role
    assert LightekIdentity::Mfa.enabled?(@owner)
    assert factor.reload.enabled?
  end
  def test_client_onboarding_evidence_is_scoped_to_its_isolated_member_site
    keys = %w[LIGHTEK_DEPLOYED_SITE_HOST LIGHTEK_PWA_MEMBER_BACKEND LIGHTEK_RELEASE]
    old = keys.to_h { |key| [key, ENV[key]] }
    ENV['LIGHTEK_DEPLOYED_SITE_HOST'] = @remote.host
    ENV['LIGHTEK_PWA_MEMBER_BACKEND'] = 'true'
    ENV['LIGHTEK_RELEASE'] = 'test-release'
    sign_in
    Current.session = Struct.new(:connect_delegation, :user, :mfa_verified_at) do
      def mfa_enrollment_only? = false
    end.new({}, @owner, nil)
    headers = {'X-Pwa-Test-User'=>@owner.id.to_s}
    @browser.get '/test/member-onboarding', headers: headers
    assert_equal 200, @browser.response.status
    assert_equal false, JSON.parse(@browser.response.body)['mfa_verified']
    ENV['LIGHTEK_PWA_MEMBER_BACKEND'] = 'false'
    @browser.get '/test/member-onboarding', headers: headers
    assert_equal 403, @browser.response.status
    ENV['LIGHTEK_PWA_MEMBER_BACKEND'] = 'true'
    @remote.update!(manifest: {'pwa_member'=>@config.merge('mode'=>'dedicated')})
    @browser.get '/test/member-onboarding', headers: headers
    assert_equal 403, @browser.response.status
    @remote.update!(manifest: {'pwa_member'=>@config})
    @browser.get '/test/member-onboarding', headers: {'X-Pwa-Test-User'=>@operator.id.to_s}
    assert_equal 403, @browser.response.status
  ensure
    old&.each { |key,value| value.nil? ? ENV.delete(key) : ENV[key]=value }
    Current.session = nil
  end
  def test_staff_and_business_accounts_and_dedicated_instances_are_not_reclassified
    %w[admin super_admin white_label].each do |source_role|
      @owner.update!(role: 'admin'); @data['account_role'] = source_role
      sign_in
      assert_equal 'admin', @owner.reload.role
      assert_equal true, JSON.parse(@browser.response.body)['mfa_required']
    end
    @data['account_role'] = 'client'
    @remote.update!(manifest: {'pwa_member'=>@config.merge('mode'=>'dedicated')})
    sign_in
    assert_equal 'admin', @owner.reload.role
    @remote.update!(manifest: {'pwa_member'=>@config.merge('paid_plan'=>'business')})
    sign_in
    assert_equal 'admin', @owner.reload.role
  end
  def test_unmatched_owner_or_backend_identity_cannot_change_a_role
    %w[email hostname backend_key].each do |field|
      original = @data[field]; @data[field] = 'unmatched'
      sign_in
      assert_equal 401, @browser.response.status
      assert_equal 'admin', @owner.reload.role
      @data[field] = original
    end
  end
  def test_request_role_parameter_is_not_an_authoritative_identity
    @data.delete('account_role')
    sign_in
    assert_equal 'admin', @owner.reload.role
    assert_equal true, JSON.parse(@browser.response.body)['mfa_required']
  end
  def bootstrap_config
    {'domain'=>@remote.host, 'owner_email'=>@owner.email_address, 'owner_role'=>'admin',
     'owner_password'=>'test-password-only', 'site_name'=>'Member space', 'pwa_member'=>@config}
  end
  def run_bootstrap(config, site)
    site.manifest = {'lightek_website_bootstrap'=>1}
    counts = Struct.new(:count).new(1)
    pages = Struct.new(:published).new(counts)
    home = Struct.new(:sections).new(counts)
    site.define_singleton_method(:pages) { pages }
    site.define_singleton_method(:home_page) { home }
    DymondSite::Site.stub(:find_or_initialize_by, site) do
      LightekSettings::SiteDomain.stub(:verify!, true) { LightekWebsite::Bootstrap.call(config) }
    end
  end
  def test_packaged_bootstrap_creates_a_free_member_as_client_and_can_be_rerun
    @owner.update!(email_address: 'old@example.test')
    config = bootstrap_config.merge('owner_email'=>'new-member@example.test')
    site = DymondSite::Site.new(host: @remote.host)
    result = run_bootstrap(config, site)
    user = User.find(result.fetch(:owner_id))
    assert_equal 'client', user.role
    assert_equal user.id, run_bootstrap(config, site).fetch(:owner_id)
    assert_equal 'client', user.reload.role
  end
  def test_general_website_bootstrap_retains_staff_administrator_roles
    config = bootstrap_config.except('pwa_member')
    run_bootstrap(config, @remote)
    assert_equal 'admin', @owner.reload.role
    config['owner_role'] = 'super_admin'
    run_bootstrap(config, @remote)
    assert_equal 'super_admin', @owner.reload.role
  end
end
