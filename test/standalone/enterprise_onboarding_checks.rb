# First-use password + owner-enrollment evidence using real bcrypt, token binding,
# Rails HTTP controllers/views, MFA, database sessions and mailer templates.
require_relative 'enterprise_form_origin_checks'
require 'action_mailer'
require 'active_job'
require 'bcrypt'
ActiveModel::SecurePassword.min_cost = true
ActiveRecord::Schema.define do
  add_column :users, :password_digest, :string
  add_column :users, :last_name, :string
end
source = ROOT.join('db/migrate/20261114000000_add_first_use_password_setup.rb').read
source = source.gsub('Migration[8.0]', "Migration[#{ActiveRecord::VERSION::MAJOR >= 8 ? '8.0' : '7.2'}]")
eval(source, TOPLEVEL_BINDING)
AddFirstUsePasswordSetup.new.migrate(:up)
ActiveRecord::Base.connection.add_column :lightek_commerce_orders, :customer_email, :string
LightekCommerce::Order.reset_column_information
User.reset_column_information
require ROOT.join('app/models/concerns/first_use_password')
GlobalID.app = 'enterprise-fixture'
class User
  include GlobalID::Identification
  has_many :agency_clients, class_name: 'User', foreign_key: :agency_id
  remove_method :authenticate
  singleton_class.remove_method :authenticate_by
  has_secure_password
  include FirstUsePassword
  generates_token_for :password_reset, expires_in: 20.minutes do
    password_salt.last(10)
  end
  # Existing enterprise fixtures create users without passwords. Populate those
  # test records only; actual controllers/concern and token verification run below.
  before_validation(on: :create) { self.password = self.password_confirmation = 'fixture-password' if password_digest.blank? }
end
User.generated_token_verifier = ActiveSupport::MessageVerifier.new('onboarding-fixture-token-key-' * 4, serializer: JSON)
require ROOT.join('app/services/lightek_design/fonts')
require ROOT.join('app/services/lightek_design/authentication_branding')
FixtureAuthBrand = Class.new(LightekDesign::AuthenticationBranding) { def logo_url = nil }
ApplicationController.helper(Module.new do
  def authentication_branding = FixtureAuthBrand.new(nil)
end)
require ROOT.join('app/mailers/application_mailer')
require ROOT.join('app/mailers/passwords_mailer')
require ROOT.join('app/mailers/lightek_commerce/instance_ready_mailer')
ActionMailer::Base.view_paths = [ROOT.join('app/views')]
ActionMailer::Base.delivery_method = :test
ActionMailer::Base.include EnterpriseHarness.routes.url_helpers
ActionMailer::Base.default_url_options = {host: 'example.test', protocol: 'https'}
ActiveJob::Base.queue_adapter = :test
PasswordsMailer.include EnterpriseHarness.routes.url_helpers
LightekCommerce::InstanceReadyMailer.include EnterpriseHarness.routes.url_helpers
require ROOT.join('app/controllers/passwords_controller')
require ROOT.join('app/controllers/account_setups_controller')
require ROOT.join('app/controllers/identity_onboarding_controller')
require ROOT.join('app/controllers/dashboard/agencies_controller')
require ROOT.join('app/services/gatekeeper/website_readiness')

class EnterpriseOnboardingChecks < EnterpriseHttpChecks
  def self.runnable_methods = super.grep(/test_onboarding_/)
  def setup
    super
    https!
    @old_host = ENV['LIGHTEK_DEPLOYED_SITE_HOST']
    @old_release = ENV['LIGHTEK_RELEASE']
    ENV.delete('LIGHTEK_DEPLOYED_SITE_HOST')
    ActionMailer::Base.deliveries.clear
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    @controllers = [PasswordsController, AccountSetupsController]
    @controllers.each { |c| c.allow_forgery_protection = true; c.forgery_protection_origin_check = true }
  end
  def teardown
    @controllers.each { |c| c.allow_forgery_protection = false; c.forgery_protection_origin_check = false }
    @old_host ? ENV['LIGHTEK_DEPLOYED_SITE_HOST'] = @old_host : ENV.delete('LIGHTEK_DEPLOYED_SITE_HOST')
    @old_release ? ENV['LIGHTEK_RELEASE'] = @old_release : ENV.delete('LIGHTEK_RELEASE')
    super
  end
  def pending_user
    User.create!(email_address: 'new-client@example.test', role: 'admin', first_name: 'New', password_setup_required: true,
      password: 'unknown-bootstrap-password', password_confirmation: 'unknown-bootstrap-password')
  end
  def csrf = Nokogiri::HTML(response.body).at_css('input[name="authenticity_token"]')['value']
  def open_setup(user)
    @setup_token = user.generate_token_for(:password_setup)
    get edit_account_setup_path(@setup_token)
    assert_response :success
    assert_includes response.body, 'no temporary or previous password is needed'
    assert_equal 'same-origin', response.headers['Referrer-Policy']
    csrf
  end
  def test_onboarding_invitation_is_queued_only_for_pending_accounts
    client = pending_user
    assert ActiveJob::Base.queue_adapter.enqueued_jobs.any? { |job| job[:job].name.include?('MailDelivery') }
    mail = PasswordsMailer.reset(client).deliver_now
    assert_equal 'Set up your Lightek account', mail.subject
    assert_equal [client.email_address], mail.to
    assert_includes mail.text_part.decoded, '/account/setup/'
    refute_includes mail.to_s, 'unknown-bootstrap-password'
    assert_includes mail.text_part.decoded, '20 minutes'
    assert_raises(ArgumentError) { @employer.send_password_setup_invitation! }
  end
  def test_onboarding_client_chooses_first_password_then_mfa_is_still_required
    client = pending_user
    token = open_setup(client)
    put account_setup_path(@setup_token), params: {password: 'chosen-password', password_confirmation: 'chosen-password', authenticity_token: token}, headers: {'Origin' => 'https://example.test'}
    assert_redirected_to new_session_path
    refute client.reload.password_setup_required?
    assert client.authenticate('chosen-password')
    refute client.authenticate('unknown-bootstrap-password')
    assert_equal 0, client.sessions.count
    get edit_account_setup_path(@setup_token)
    assert_redirected_to new_password_path
    post session_path, params: {email_address: client.email_address, password: 'chosen-password'}
    assert_redirected_to identity_security_path
    assert client.sessions.last.mfa_enrollment_only?
    get '/after-login'
    assert_redirected_to identity_security_path
    @controllers << IdentitySecurityController
    IdentitySecurityController.allow_forgery_protection = true
    IdentitySecurityController.forgery_protection_origin_check = true
    get identity_security_path
    post enroll_identity_security_path, params: {password: 'chosen-password', authenticity_token: csrf}, headers: {'Origin' => 'https://example.test'}
    assert_response :success
    factor = LightekIdentity::Factor.find_by!(user: client)
    secret = LightekIdentity::Sealed.open(factor.secret_box, context: "mfa:#{client.id}")['secret']
    post confirm_identity_security_path, params: {otp: LightekIdentity::Mfa.code(secret, Time.current.to_i / 30), authenticity_token: csrf}, headers: {'Origin' => 'https://example.test'}
    assert_response :success
    assert_includes response.body, 'Save your recovery codes'
    assert LightekIdentity::Mfa.fresh?(client.sessions.last)
    get '/after-login'
    assert_response :success
  end
  def test_onboarding_mismatched_or_blank_password_does_not_consume_invitation
    client = pending_user
    token = open_setup(client)
    put account_setup_path(@setup_token), params: {password: 'chosen-password', password_confirmation: 'different', authenticity_token: token}, headers: {'Origin' => 'https://example.test'}
    assert_response :unprocessable_entity
    assert_includes response.body, 'confirmation'
    assert client.reload.password_setup_required?
    put account_setup_path(@setup_token), params: {password: '', password_confirmation: '', authenticity_token: csrf}, headers: {'Origin' => 'https://example.test'}
    assert_response :unprocessable_entity
    assert client.reload.password_setup_required?
    assert client.authenticate('unknown-bootstrap-password')
  end
  def test_onboarding_expired_or_wrong_purpose_tokens_fail
    client = pending_user
    setup_token = client.generate_token_for(:password_setup)
    reset_token = client.generate_token_for(:password_reset)
    get edit_account_setup_path(reset_token)
    assert_redirected_to new_password_path
    travel 21.minutes
    get edit_account_setup_path(setup_token)
    assert_redirected_to new_password_path
    assert client.reload.password_setup_required?
  end
  def test_onboarding_missing_csrf_does_not_set_a_password
    client = pending_user
    open_setup(client)
    assert_raises(ActionController::InvalidAuthenticityToken) do
      put account_setup_path(@setup_token), params: {password: 'chosen-password', password_confirmation: 'chosen-password'}, headers: {'Origin' => 'https://example.test'}
    end
    assert client.reload.password_setup_required?
  end
  def test_onboarding_password_reset_revokes_sessions_but_keeps_existing_mfa
    login(@employer)
    token = @employer.generate_token_for(:password_reset)
    get edit_password_path(token)
    assert_response :success
    put password_path(token), params: {password: 'replacement-password', password_confirmation: 'replacement-password', authenticity_token: csrf}, headers: {'Origin' => 'https://example.test'}
    assert_redirected_to new_session_path
    assert_equal 0, @employer.sessions.count
    assert LightekIdentity::Mfa.enabled?(@employer)
    post session_path, params: {email_address: @employer.email_address, password: 'replacement-password'}
    assert_redirected_to identity_challenge_path
    get edit_password_path(token)
    assert_redirected_to new_password_path
  end
  def test_onboarding_status_requires_an_authenticated_matching_owner
    ENV['LIGHTEK_DEPLOYED_SITE_HOST'] = 'example.test'
    ENV['LIGHTEK_RELEASE'] = 'fixture-release'
    site = DymondSite::Site.create!(host: 'example.test', name: 'Owner app', tenant: @employer)
    @employer.update!(role: 'admin')
    get '/identity/onboarding-status'
    assert_response :unauthorized
    post session_path, params: {email_address: @employer.email_address, password: 'fixture-password'}
    assert_redirected_to identity_security_path
    get '/identity/onboarding-status'
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal @employer.email_address, data['owner_email']
    assert_equal site.id, data['site_id']
    assert_equal 'mfa_enrollment_only', data['session_scope']
    assert data['password_authenticated']
    refute data['mfa_verified']
    get '/after-login'
    assert_redirected_to identity_security_path
    delete session_path
    post session_path, params: {email_address: @other.email_address, password: 'fixture-password'}
    get '/identity/onboarding-status'
    assert_response :forbidden
  end
  def test_onboarding_status_is_not_a_central_or_cross_host_auth_bypass
    get '/identity/onboarding-status'
    assert_response :not_found
    ENV['LIGHTEK_DEPLOYED_SITE_HOST'] = 'other.example.test'
    get '/identity/onboarding-status'
    assert_response :not_found
  end
  def test_onboarding_agency_created_client_gets_invitation_and_scoped_resend
    login(@employer)
    post create_client_dashboard_agency_path(@employer), params: {client: {first_name: 'New', last_name: 'Client', email_address: 'agency-client@example.test'}}
    assert_redirected_to dashboard_agencies_path
    client = @employer.agency_clients.find_by!(email_address: 'agency-client@example.test')
    assert client.password_setup_required?
    assert ActiveJob::Base.queue_adapter.enqueued_jobs.any?
    before = ActiveJob::Base.queue_adapter.enqueued_jobs.size
    post send_setup_invitation_dashboard_agency_path(@employer), params: {client_id: client.id}
    assert_redirected_to dashboard_agencies_path
    assert_equal before + 1, ActiveJob::Base.queue_adapter.enqueued_jobs.size
    assert_raises(ActiveRecord::RecordNotFound) do
      post send_setup_invitation_dashboard_agency_path(@employer), params: {client_id: @other.id}
    end
  end
  def test_onboarding_deployed_agencies_send_invites_but_bootstrap_can_defer
    ENV['LIGHTEK_DEPLOYED_SITE_HOST'] = 'example.test'
    pending_user
    assert ActiveJob::Base.queue_adapter.enqueued_jobs.any?
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    User.create!(email_address: 'bootstrap@example.test', role: 'admin', first_name: 'Owner',
      password_setup_required: true, skip_password_setup_invitation: true)
    assert_empty ActiveJob::Base.queue_adapter.enqueued_jobs
  end
  def test_onboarding_forgot_password_reissues_pending_setup_without_disclosing_account
    client = pending_user
    get new_password_path
    post passwords_path, params: {email_address: client.email_address, authenticity_token: csrf}, headers: {'Origin' => 'https://example.test'}
    assert_redirected_to new_session_path
    assert_includes flash[:notice], 'if user'
    assert client.reload.password_setup_required?
    assert_equal 'Set up your Lightek account', PasswordsMailer.reset(client).subject
  end

  def test_onboarding_ready_mail_guides_a_new_purchaser_before_instance_setup
    client = pending_user
    order = LightekCommerce::Order.create!(customer_email: client.email_address, provisioned_at: Time.current)
    mail = LightekCommerce::InstanceReadyMailer.ready(order.id).deliver_now
    assert_includes mail.text_part.decoded, '/account/setup/'
    assert_includes mail.html_part.decoded, '/account/setup/'
    assert_includes mail.text_part.decoded, '/my/installations/'
    assert_includes mail.text_part.decoded, 'own sign-in and password'
    refute_includes mail.to_s, 'unknown-bootstrap-password'
  end
  def test_onboarding_queue_failure_preserves_pending_account_for_retry
    PasswordsMailer.stub(:reset, ->(*) { raise IOError, 'fixture queue unavailable' }) do
      client = pending_user
      assert client.persisted?
      assert client.password_setup_required?
      assert client.password_setup_invitation_error
    end
  end

end
