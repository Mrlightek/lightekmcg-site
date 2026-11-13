# Real Rails HTTP sessions, authenticator, grants and sensitive controllers.
# The cross-server network boundary is replaced; both sides' production
# controllers and the existing peer bearer authentication still execute.
require_relative 'enterprise_http_checks'
require ROOT.join('app/models/concerns/account_hierarchy')
class User
  include AccountHierarchy
  belongs_to :agency, class_name: 'User', optional: true
  def agency_profile = nil
end
module DymondSite
  class Site < ApplicationRecord
    self.table_name = 'dymond_site_sites'
    belongs_to :tenant, polymorphic: true
  end
end
require ROOT.join('app/services/lightek_settings/website_identity')
require ROOT.join('app/services/lightek_settings/site_domain')
%w[connection event grant].each { |f| require ROOT.join("app/models/lightek_connect/#{f}") }
require ROOT.join('app/helpers/nevaeh_control_center_helper')
%w[mfa_handoff workspace].each { |f| require ROOT.join("app/services/lightek_connect/#{f}") }
require ROOT.join('app/controllers/concerns/lightek_connect/delegated_session')
ApplicationController.include LightekConnect::DelegatedSession
require ROOT.join('app/controllers/connect_management_controller')
ConnectManagementController.layout false
%w[availability booking federation/client federation/issuer].each { |f| require ROOT.join("app/services/lightek_reservations/#{f}") }
# The paid order is only used for peer.active? in this narrowly scoped fixture.
ActiveRecord::Schema.define do
  create_table(:lightek_commerce_orders) { |t| t.datetime :paid_at; t.datetime :provisioned_at; t.string :status }
end
module LightekCommerce
  class Order < ApplicationRecord
    self.table_name = 'lightek_commerce_orders'
  end
end
source = ROOT.join('db/migrate/20261108200000_add_reservation_federation.rb').read
# Reservation intents belong to another acceptance suite; use the actual peer table.
source = source.split('    create_table :lightek_reservation_intents').first + "  end\nend\n"
eval(source, TOPLEVEL_BINDING)
AddReservationFederation.new.migrate(:up)
require ROOT.join('app/models/lightek_reservations/peer')
module Api; end
require ROOT.join('app/controllers/api/reservation_federation_controller')
require ROOT.join('app/controllers/api/connect_federation_controller')

class EnterpriseConnectMfaChecks < EnterpriseHttpChecks
  def self.runnable_methods = super.grep(/test_connect_/)
  def setup
    LightekReservations::Peer.delete_all
    LightekCommerce::Order.delete_all
    super
    @other.update!(agency: @employer)
    @connection, = LightekConnect::Connection.issue!(user: @employer, platform: 'wordpress', label: 'MFA acceptance')
    @site = DymondSite::Site.create!(tenant: @other, name: 'Client', host: 'client.example.test')
    @client_book = LightekAccounting::Book.create!(employer: @other, name: 'Client books')
    @token = "#{SecureRandom.uuid}.#{SecureRandom.hex(32)}"
    order = LightekCommerce::Order.create!(paid_at: Time.current, provisioned_at: Time.current, status: 'paid')
    @peer = LightekReservations::Peer.create!(site: @site, merchant: @other, order: order, key: @token.split('.').first, token_digest: Digest::SHA256.hexdigest(@token))
    host! 'lightekmcg.com'
    https!
  end
  def grant(site: nil, destination: '/after-login')
    @code = LightekConnect::Grant.issue!(connection: @connection, site: site, destination: destination)
    @grant = LightekConnect::Grant.find_by!(code_digest: LightekConnect::Connection.digest(@code))
  end
  def central_login
    login(@employer)
    @source = @employer.sessions.last
  end
  def approve_local
    central_login
    grant
    post '/connect/management', params: {code: @code, mfa_verified: true}
    assert_redirected_to '/after-login'
    assert @grant.reload.consumed_at
    @delegated = @employer.sessions.order(:id).last
    refute_equal @source, @delegated
    assert_nil @delegated.mfa_verified_at
  end
  def authorize_remote
    central_login
    grant(site: @site)
    post '/connect/management', params: {code: @code}
    assert_redirected_to "https://client.example.test/connect/management?code=#{@code}"
    assert @grant.reload.approved_at
    assert_nil @grant.consumed_at
  end
  def remote_browser
    browser = open_session
    browser.host! @site.host
    browser.https!
    browser
  end
  # Forward authenticated federation HTTP requests to the real issuer controller.
  def federation_request(path, method:, body:)
    target_session = Current.session
    issuer = open_session
    issuer.host! 'lightekmcg.com'
    issuer.https!
    issuer.public_send(method, "/api/reservations/federation/#{path}", params: body,
      headers: {'Authorization' => "Bearer #{@token}"}, as: :json)
    raise LightekReservations::Federation::Client::Unavailable, 'Issuer denied verification' unless issuer.response.successful?
    JSON.parse(issuer.response.body)
  ensure
    Current.session = target_session
  end
  def with_remote
    config = {'origin' => 'https://lightekmcg.com', 'credential_slug' => 'test-federation'}
    @site.update!(manifest: {'lightek_reservation_federation' => config})
    transport = Object.new
    callback = method(:federation_request)
    transport.define_singleton_method(:request) { |path, **options| callback.call(path, **options) }
    LightekReservations::Federation::Client.stub(:new, transport) { yield }
  end
  def open_remote(browser)
    browser.post '/connect/management', params: {code: @code}
    assert_equal 302, browser.response.status
    assert @grant.reload.consumed_at
  end
  def test_connect_preview_never_approves_or_consumes
    grant
    get '/connect/management', params: {code: @code}
    assert_response :success
    assert_includes response.body, 'authenticator'
    assert_nil @grant.reload.approved_at
    assert_nil @grant.consumed_at
    assert_equal 0, Session.count
  end
  def test_connect_token_and_browser_claims_are_not_mfa
    grant
    post '/connect/management', params: {code: @code, mfa_verified: true, user_id: @employer.id, mfa_verified_at: Time.current.iso8601}
    assert_redirected_to new_session_path
    assert_nil @grant.reload.approved_at
    assert_nil @grant.consumed_at
    assert_equal 0, Session.count
    post session_path, params: {email_address: @employer.email_address, password: 'fixture-password'}
    follow_redirect!
    post '/connect/management', params: {code: @code}
    assert_redirected_to identity_security_path
    assert_nil @grant.reload.approved_at
  end
  def test_connect_step_up_returns_to_the_original_handoff
    central_login
    @source.update!(mfa_verified_at: 13.hours.ago)
    grant
    post '/connect/management', params: {code: @code}
    assert_redirected_to identity_challenge_path
    assert_nil @grant.reload.approved_at
    factor = LightekIdentity::Factor.find_by!(user: @employer)
    seed = LightekIdentity::Sealed.open(factor.secret_box, context: "mfa:#{@employer.id}")['secret']
    travel 61.seconds
    post identity_challenge_path, params: {otp: LightekIdentity::Mfa.code(seed, Time.current.to_i / 30)}
    assert_redirected_to "/connect/management?code=#{@code}"
    follow_redirect!
    assert_response :success
    post '/connect/management', params: {code: @code}
    assert_redirected_to '/after-login'
    assert @grant.reload.consumed_at
  end
  def test_connect_wrong_agency_and_unapproved_federation_redemption_are_denied
    login(@other)
    grant(site: @site)
    post '/connect/management', params: {code: @code}
    assert_response :forbidden
    post '/api/reservations/federation/connect/redeem', params: {code: @code}, headers: {'Authorization' => "Bearer #{@token}"}, as: :json
    assert_response :forbidden
    assert_nil @grant.reload.consumed_at
  end
  def test_connect_local_mfa_opens_allowed_sensitive_pages_and_keeps_scope
    approve_local
    get workspace
    assert_response :success
    get dashboard_accounting_path(employer_id: @other.id, book_id: @client_book.id)
    assert_response :not_found
    get dashboard_directory_path(employer_id: @employer.id)
    assert_response :success
    post dashboard_directory_policy_path(employer_id: @employer.id), params: {mfa_required: '0', password: 'fixture-password'}
    assert_response :forbidden
    get identity_security_path
    assert_response :forbidden
    assert @source.reload.mfa_verified_at
  end
  def test_connect_local_source_logout_ends_access
    approve_local
    @source.destroy!
    get workspace
    assert_response :unauthorized
    refute Session.exists?(@delegated.id)
    assert_nil @grant.reload.authorization_session_id
  end
  def test_connect_local_legacy_delegation_cannot_become_owner_mfa
    approve_local
    @delegated.update!(connect_delegation: {'local' => true, 'connection_id' => @connection.id})
    get workspace
    assert_response :unauthorized
    refute Session.exists?(@delegated.id)
  end
  def test_connect_remote_owner_without_factor_uses_verified_agency_mfa
    authorize_remote
    browser = remote_browser
    with_remote do
      open_remote(browser)
      browser.get dashboard_accounting_path(employer_id: @other.id, book_id: @client_book.id)
      assert_equal 200, browser.response.status
      browser.get workspace
      assert_equal 404, browser.response.status
      assert_not LightekIdentity::Mfa.enabled?(@other)
      target = @other.sessions.last
      assert_nil target.mfa_verified_at
      browser.post dashboard_accounting_books_path, params: {employer_id: @other.id, book: {name: 'Delegated client book'}}
      assert_equal 303, browser.response.status
      audit = LightekConnect::Event.where(action: 'instance_request').last
      assert_equal @employer.email_address, audit.details['actor']
      assert_equal @grant.id, audit.details['grant_id']
      @connection.revoke!
      browser.get '/after-login'
      assert_equal 401, browser.response.status
      refute Session.exists?(target.id)
    end
  end
  def test_connect_remote_policy_opt_out_fails_closed
    authorize_remote
    browser = remote_browser
    with_remote do
      open_remote(browser)
      LightekIdentity::OrganizationPolicy.create!(employer: @other, mfa_required: true, connect_mfa_allowed: false)
      browser.get '/after-login'
      assert_equal 401, browser.response.status
      assert LightekIdentity::OrganizationPolicy.find_by!(employer: @other).mfa_required?
    end
  end
  def test_connect_grant_replay_is_denied
    authorize_remote
    @grant.approve!(@source)
    original_expiry = @grant.expires_at
    assert_equal original_expiry, @grant.reload.expires_at
    browser = remote_browser
    with_remote do
      open_remote(browser)
      thief = remote_browser
      thief.post '/connect/management', params: {code: @code}
      assert_equal 403, thief.response.status
    end
  end
  def test_connect_pending_enrollment_preserves_the_handoff
    grant
    post '/connect/management', params: {code: @code}
    post session_path, params: {email_address: @employer.email_address, password: 'fixture-password'}
    post '/connect/management', params: {code: @code}
    assert_redirected_to identity_security_path
    post enroll_identity_security_path, params: {password: 'fixture-password'}
    assert_response :success
    factor = LightekIdentity::Factor.find_by!(user: @employer)
    seed = LightekIdentity::Sealed.open(factor.secret_box, context: "mfa:#{@employer.id}")['secret']
    post confirm_identity_security_path, params: {otp: LightekIdentity::Mfa.code(seed, Time.current.to_i / 30)}
    assert_response :success
    assert_includes response.body, "href=\"/connect/management?code=#{@code}\""
    post '/connect/management', params: {code: @code}
    assert_redirected_to '/after-login'
    assert @grant.reload.consumed_at
  end
  def test_connect_role_demotion_ends_local_access
    approve_local
    @employer.update!(role: 'client')
    get '/after-login'
    assert_response :unauthorized
    refute Session.exists?(@delegated.id)
  end
  def test_connect_factor_disable_ends_local_access
    approve_local
    LightekIdentity::Factor.find_by!(user: @employer).destroy!
    get '/after-login'
    assert_response :unauthorized
    refute Session.exists?(@delegated.id)
  end
  def test_connect_expired_pending_and_approved_grants_cannot_be_redeemed
    central_login
    grant
    @grant.update!(expires_at: 1.second.ago)
    post '/connect/management', params: {code: @code}
    assert_response :forbidden
    assert_nil @grant.reload.approved_at
    grant
    @grant.approve!(@source)
    @grant.update!(expires_at: 1.second.ago)
    assert_raises(Gatekeeper::Hosting::Access::Denied) { LightekConnect::Grant.consume!(code: @code, site: nil) }
    assert_nil @grant.reload.consumed_at
  end
  def test_connect_delegation_expiry_cannot_start_a_client_owner_challenge
    authorize_remote
    browser = remote_browser
    with_remote do
      open_remote(browser)
      @grant.update!(delegation_expires_at: 1.second.ago)
      browser.get '/after-login'
      assert_equal 401, browser.response.status
      assert_not browser.response.redirect?
      assert_equal 0, @other.sessions.count
    end
  end
  def test_connect_client_relationship_removal_is_rechecked
    authorize_remote
    browser = remote_browser
    with_remote do
      open_remote(browser)
      @other.update!(agency: nil)
      browser.get '/after-login'
      assert_equal 401, browser.response.status
      assert_equal 0, @other.sessions.count
    end
  end
  def test_connect_remote_issuer_outage_denies_access
    authorize_remote
    browser = remote_browser
    with_remote { open_remote(browser) }
    transport = Object.new
    transport.define_singleton_method(:request) { |*args, **options| raise LightekReservations::Federation::Client::Unavailable, 'test outage' }
    LightekReservations::Federation::Client.stub(:new, transport) do
      browser.get '/after-login'
      assert_equal 401, browser.response.status
      assert_equal 0, @other.sessions.count
    end
  end
  def test_connect_remote_owner_transfer_is_denied
    authorize_remote
    browser = remote_browser
    with_remote do
      open_remote(browser)
      @site.update!(tenant: @employer)
      browser.get '/after-login'
      assert_equal 401, browser.response.status
    end
  end
  def test_connect_federation_requires_the_correct_peer_and_site
    authorize_remote
    post '/api/reservations/federation/connect/redeem', params: {code: @code}, headers: {'Authorization' => 'Bearer invalid'}, as: :json
    assert_response :unauthorized
    other_site = DymondSite::Site.create!(tenant: @employer, name: 'Unrelated peer', host: 'other.example.test')
    @peer.update!(site: other_site)
    post '/api/reservations/federation/connect/redeem', params: {code: @code}, headers: {'Authorization' => "Bearer #{@token}"}, as: :json
    assert_response :not_found
    assert_nil @grant.reload.consumed_at
  end
  def test_connect_claimed_mfa_without_verified_server_response_is_rejected
    authorize_remote
    browser = remote_browser
    with_remote { open_remote(browser) }
    transport = Object.new
    owner_email = @other.email_address
    transport.define_singleton_method(:request) { |*args, **options| {'allowed' => true, 'owner_email' => owner_email} }
    LightekReservations::Federation::Client.stub(:new, transport) do
      browser.get '/after-login'
      assert_equal 401, browser.response.status
      assert_equal 0, @other.sessions.count
    end
  end
  def test_connect_post_requires_csrf_and_does_not_consume_on_get
    central_login
    grant
    ConnectManagementController.allow_forgery_protection = true
    assert_raises(ActionController::InvalidAuthenticityToken) { post '/connect/management', params: {code: @code} }
    assert_nil @grant.reload.approved_at
    assert_nil @grant.consumed_at
  ensure
    ConnectManagementController.allow_forgery_protection = false
  end

  def test_connect_remote_source_session_logout_ends_client_access
    authorize_remote
    browser = remote_browser
    with_remote do
      open_remote(browser)
      @source.destroy!
      browser.get '/after-login'
      assert_equal 401, browser.response.status
      assert_equal 0, @other.sessions.count
    end
  end
  def test_connect_delegated_session_cannot_approve_another_handoff
    approve_local
    grant
    post '/connect/management', params: {code: @code}
    assert_redirected_to new_session_path
    assert_nil @grant.reload.approved_at
    assert_nil @grant.authorization_session_id
  end
  def test_connect_disabled_source_sso_revokes_existing_handoff
    approve_local
    oidc = LightekIdentity::Connection.create!(employer: @employer, slug: 'source-sso', issuer: 'https://idp.example.com',
      authorization_endpoint: 'https://idp.example.com/authorize', token_endpoint: 'https://idp.example.com/token',
      jwks_uri: 'https://idp.example.com/keys', client_id: 'fixture', enabled: false)
    @source.update!(identity_connection_id: oidc.id)
    get '/after-login'
    assert_response :unauthorized
    refute Session.exists?(@delegated.id)
  end

end
