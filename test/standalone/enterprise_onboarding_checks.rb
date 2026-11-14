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
require ROOT.join('app/controllers/dashboard/account_settings_controller')
require ROOT.join('app/controllers/dashboard/client_home_controller')
require ROOT.join('app/models/lightek_agency/site_membership')
require ROOT.join('app/services/lightek_agency/access')
require ROOT.join('app/services/lightek_commerce/installations')
ActiveRecord::Schema.define do
  add_column :lightek_commerce_orders, :created_at, :datetime
  create_table(:lightek_agency_site_memberships) do |t|
    t.integer :user_id; t.integer :site_id; t.integer :granted_by_id; t.string :role
  end
end
LightekCommerce::Order.reset_column_information
[Dashboard::AccountSettingsController, Dashboard::ClientHomeController].each { |klass| klass.layout false }
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
  def capture_page(name)
    return unless (directory = ENV['MFA_QR_CAPTURE_DIR'])
    FileUtils.mkdir_p(directory)
    File.write(File.join(directory, name), response.body)
  end
  def open_client_home
    LightekCommerce::Installations.stub(:scope_for, ->(actor) {
      assert_equal @other.id, actor.id
      LightekCommerce::Order.none
    }) { get dashboard_client_home_path }
  end
  def csrf = Nokogiri::HTML(response.body).at_css('input[name="authenticity_token"]')['value']
  def open_setup(user)
    @setup_token = user.generate_token_for(:password_setup)
    get edit_account_setup_path(@setup_token)
    assert_response :success
    assert_includes response.body, 'no temporary or previous password is needed'
    assert_equal 'same-origin', response.headers['Referrer-Policy']
    capture_page('password-setup.html')
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
    assert_select '[data-mfa-recovery-codes] code', count: 10
    assert_select 'button[data-mfa-recovery-download][type="button"][hidden]', count: 1
    assert_select 'script[src="/lightek/mfa-recovery.js"]', count: 1
    assert_equal 'no-store', response.headers['Cache-Control']
    capture_page('recovery.html')
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

  def test_onboarding_client_lands_on_a_scoped_home_and_can_open_personal_settings
    client = @other
    client.update!(agency: @employer)
    DymondSite::Site.create!(tenant: @employer, name: 'Private agency site', host: 'private-agency.example.test')
    login(client)
    assert_redirected_to dashboard_client_home_url
    open_client_home
    assert_response :success
    assert_includes response.body, 'Your workspace'
    assert_includes response.body, 'No websites have been assigned'
    refute_includes response.body, 'Private agency site'
    capture_page('client-home.html')
    get dashboard_settings_home_path
    assert_response :success
    assert_select 'a[href="/identity/security"] strong', text: 'Sign-in security'
    refute_includes response.body, 'Compute providers'
    refute_includes response.body, 'Credential vault'
    assert_equal %w[no-store private], response.headers['Cache-Control'].split(',').map(&:strip).sort
    capture_page('client-settings.html')
  end

  def test_onboarding_client_home_only_lists_owned_or_explicitly_delegated_sites
    client = @other
    owned = DymondSite::Site.create!(tenant: client, name: 'Owned client site', host: 'owned.example.test')
    delegated = DymondSite::Site.create!(tenant: @employer, name: 'Delegated site', host: 'delegated.example.test')
    DymondSite::Site.create!(tenant: @employer, name: 'Never assigned', host: 'secret.example.test')
    LightekAgency::SiteMembership.create!(site: delegated, user: client, granted_by: @employer, role: 'designer')
    login(client)
    open_client_home
    assert_response :success
    assert_includes response.body, owned.name
    assert_includes response.body, delegated.name
    refute_includes response.body, 'Never assigned'
    refute_includes response.body, 'secret.example.test'
  ensure
    LightekAgency::SiteMembership.delete_all
  end

  def test_onboarding_bookkeeping_unavailable_explains_access_without_granting_it
    original = User.instance_method(:can_access_feature?)
    User.define_method(:can_access_feature?) { |*| false }
    login(@other)
    get dashboard_accounting_path
    assert_response :forbidden
    assert_includes response.body, 'active bookkeeping entitlement'
    assert_select 'a[href="/after-login/servers"]', text: 'Back to Servers & Applications'
    refute_includes response.body, @book.name
    post dashboard_accounting_books_path, params: {book: {name: 'Must not be created'}}
    assert_response :forbidden
    refute LightekAccounting::Book.exists?(name: 'Must not be created')
  ensure
    User.define_method(:can_access_feature?, original) if original
  end

  def test_onboarding_missing_or_foreign_bookkeeping_record_has_a_safe_explanation
    login(@other)
    get dashboard_accounting_path(employer_id: @employer.id, book_id: @book.id)
    assert_response :not_found
    assert_includes response.body, 'could not be found for your account'
    refute_includes response.body, @book.name
  end

  def test_onboarding_personal_settings_and_client_home_still_require_sign_in
    get dashboard_settings_home_path
    assert_redirected_to new_session_path
    get dashboard_client_home_path
    assert_redirected_to new_session_path
  end

  def test_onboarding_installed_application_launch_opens_its_admin_dashboard
    visible = LightekCommerce::Order.create!(customer_email: @other.email_address)
    LightekCommerce::Order.create!(customer_email: @employer.email_address)
    login(@other)
    LightekCommerce::Installations.stub(:scope_for, ->(actor) {
      assert_equal @other.id, actor.id
      LightekCommerce::Order.where(customer_email: actor.email_address)
    }) do
      LightekCommerce::Installations.stub(:summary, ->(order) {
        assert_equal visible.id, order.id
        {hostname: 'owned-instance.example.test', state: 'ready', ready: true, url: 'https://owned-instance.example.test'}
      }) { get dashboard_client_home_path }
    end
    assert_response :success
    assert_select 'a[href="https://owned-instance.example.test/dashboard/"][rel="noopener"]', text: 'Launch admin dashboard'
    assert_select "a[href=\"/my/installations/#{visible.id}\"]", text: 'Application details & setup'
  end

  def test_onboarding_explicit_return_destination_is_preserved_for_clients
    get '/after-login/servers'
    assert_redirected_to new_session_path
    post session_path, params: {email_address: @other.email_address, password: 'fixture-password'}
    assert_redirected_to 'https://example.test/after-login/servers'
  end

  def test_onboarding_generic_dashboard_request_returns_clients_to_their_home
    get '/dashboard'
    assert_redirected_to new_session_path
    post session_path, params: {email_address: @other.email_address, password: 'fixture-password'}
    assert_redirected_to dashboard_client_home_url
  end

  def test_onboarding_installed_owner_admin_keeps_the_admin_dashboard_landing
    @employer.update!(role: 'admin')
    login(@employer)
    assert_redirected_to dashboard_nevaeh_os_url
  end

end
