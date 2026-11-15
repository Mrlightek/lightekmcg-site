# Real account ownership, session/MFA/CSRF and DB writes. Only provider calls are stubbed.
require_relative '../../app/services/lightek_agency/package_policy'
require_relative 'enterprise_http_checks'
require 'stripe'
ActiveRecord::Schema.define do
  add_column :users, :stripe_connect_account_id, :string
  add_column :users, :stripe_connect_details_submitted, :boolean, default: false
  add_column :users, :stripe_connect_payouts_enabled, :boolean, default: false
  add_column :users, :stripe_connect_onboarded_at, :datetime
end
require ROOT.join('db/migrate/20261115110000_create_payout_connection_changes')
CreatePayoutConnectionChanges.new.migrate(:up)
require ROOT.join('app/models/lightek_payments/connection_change')
require ROOT.join('app/services/lightek_payments/payout_accounts')
require ROOT.join('app/models/lightek_commerce/payout_schedule')
ActiveRecord::Schema.define do
  create_table(:lightek_merchant_payout_schedules) do |t|
    t.references :merchant; t.string :cadence, default: 'biweekly'; t.boolean :enabled, default: true; t.datetime :next_run_at
  end
end
class User
  def stripe_connect_ready? = stripe_connect_account_id.present? && stripe_connect_details_submitted? && stripe_connect_payouts_enabled?
end
module DymondBank
  module StripeCredentials
    def self.secret_key = 'sk_test_fixture_only'
    def self.publishable_key = 'pk_test_fixture_only'
  end
end
module DymondSite
  class Site < ApplicationRecord
    self.table_name = 'dymond_site_sites'
    belongs_to :tenant, polymorphic: true
  end
end
module DymondDash
  class ApplicationController < ::ApplicationController; end
end
require ROOT.join('app/controllers/susu_payout_accounts_controller')
require ROOT.join('app/services/lightek_settings/website_identity')
require ROOT.join('app/services/lightek_reservations/federation/client')
SusuPayoutAccountsController.layout false
# Treat the test delegation as already verified by its issuer; the payout
# controller must still refuse destination changes by that delegated session.
class SusuPayoutAccountsController
  def validate_connect_delegation! = nil
  def connect_mfa_verified? = true
end
class PayoutTestCsrfController < ApplicationController
  protect_from_forgery with: :exception
  def show = render(json: {token: form_authenticity_token})
end
class PayoutAccountsChecks < EnterpriseHttpChecks
  Accounts = LightekPayments::PayoutAccounts
  def self.runnable_methods = super.grep(/^test_payout_/)
  def setup
    LightekPayments::ConnectionChange.delete_all
    LightekCommerce::PayoutSchedule.delete_all
    super
    SusuPayoutAccountsController.allow_forgery_protection = true
    SusuPayoutAccountsController.forgery_protection_origin_check = true
  end
  def teardown
    SusuPayoutAccountsController.allow_forgery_protection = false
    SusuPayoutAccountsController.forgery_protection_origin_check = false
    super
  end
  def account(user = @employer, **attributes)
    Stripe::Account.construct_from({id: 'acct_owner', metadata: {lightek_user_id: user.id.to_s}, details_submitted: true,
      payouts_enabled: true, capabilities: {transfers: 'active'}, requirements: {pending_verification: []}}.merge(attributes))
  end
  def linked(user = @employer)
    user.update!(stripe_connect_account_id: 'acct_owner', stripe_connect_details_submitted: true, stripe_connect_payouts_enabled: true)
    user
  end
  def inaccessible
    Stripe::InvalidRequestError.new('sk_live_partial account acct_wrong from provider must never appear', 'account', code: 'account_invalid', http_status: 403)
  end
  def sign_in
    login(@employer)
    get '/test/payout-csrf'
    @csrf = response.parsed_body.fetch('token')
  end
  def test_payout_fresh_status_clears_stale_ready_and_never_returns_provider_error
    linked
    Stripe::Account.stub(:retrieve, ->(*_) {raise inaccessible}) do
      assert_equal({state: 'unavailable', replaceable: true}, Accounts.status(@employer))
    end
    refute @employer.reload.stripe_connect_ready?
  end
  def test_payout_requires_active_transfers_not_just_cached_details
    linked
    Stripe::Account.stub(:retrieve, account(capabilities: {transfers: 'inactive'})) {assert_equal 'needs_information', Accounts.status(@employer)[:state]}
    refute @employer.reload.stripe_connect_ready?
    remote = account(details_submitted: false, requirements: {pending_verification: ['individual.verification.document']})
    Stripe::Account.stub(:retrieve, remote) {assert_equal 'pending_verification', Accounts.status(@employer)[:state]}
  end
  def test_payout_cannot_use_a_reference_belonging_to_another_user
    linked
    Stripe::Account.stub(:retrieve, account(@other)) {assert_equal 'unavailable', Accounts.status(@employer)[:state]}
    refute @employer.reload.stripe_connect_ready?
  end
  def test_payout_session_has_only_owner_onboarding_and_management_permissions
    linked
    calls=[]
    create=->(params,opts) {calls << [params,opts]; OpenStruct.new(client_secret: 'fixture_session_secret')}
    Stripe::Account.stub(:retrieve, account) do
      Stripe::AccountSession.stub(:create, create) do
        value=Accounts.session!(@employer, component: 'account-management')
        assert_equal 'fixture_session_secret',value[:client_secret]
      end
    end
    assert_equal 'acct_owner',calls.first.first[:account]
    assert_equal %i[account_onboarding account_management],calls.first.first[:components].keys
    refute calls.first.first[:components].values.any? { |component| component[:features].key?(:disable_stripe_user_authentication) }
    assert_equal 'sk_test_fixture_only',calls.first.last[:api_key]
  end
  def test_payout_new_accounts_are_separate_for_each_agency_generation
    agency=@employer
    client=User.create!(email_address:'client@example.test',role:'white_label')
    downstream=User.create!(email_address:'downstream@example.test',role:'client')
    calls=[]
    create=->(params,opts) {calls<<[params,opts];account(User.find(params[:metadata][:lightek_user_id]),id:"acct_#{params[:metadata][:lightek_user_id]}",details_submitted:false,payouts_enabled:false)}
    Stripe::Account.stub(:create, create) do
      Stripe::AccountSession.stub(:create, OpenStruct.new(client_secret:'fixture_session_secret')) do
        [agency,client,downstream].each { |owner| Accounts.session!(owner) }
      end
    end
    assert_equal 3,calls.map { |entry| entry.last[:idempotency_key] }.uniq.size
    assert_equal [agency.id,client.id,downstream.id].map(&:to_s),calls.map { |entry| entry.first[:metadata][:lightek_user_id] }
    assert_equal 3,[agency,client,downstream].map { |owner| owner.reload.stripe_connect_account_id }.uniq.size
  end
  def test_payout_key_mode_mismatch_fails_before_account_creation
    Stripe::Account.stub(:create, ->(*) {flunk 'must not create an account'}) do
      DymondBank::StripeCredentials.stub(:publishable_key,'pk_live_wrong_mode') {assert_raises(Accounts::Unavailable) {Accounts.session!(@employer)}}
    end
    assert_nil @employer.reload.stripe_connect_account_id
  end
  def test_payout_explicit_replacement_keeps_old_reference_and_requires_new_verification
    linked
    retrieve=->(id,*) {id.nil? ? OpenStruct.new(id:'acct_platform') : (raise inaccessible)}
    Stripe::Account.stub(:retrieve,retrieve) do
      Stripe::Account.stub(:create,account(id:'acct_replacement',details_submitted:false,payouts_enabled:false)) {Accounts.replace_unavailable!(@employer)}
    end
    assert_equal 'acct_replacement',@employer.reload.stripe_connect_account_id
    refute @employer.stripe_connect_ready?
    change=LightekPayments::ConnectionChange.find_by!(user:@employer)
    assert_equal 'acct_owner',change.previous_account_id
    assert_equal 'acct_replacement',change.replacement_account_id
  end
  def test_payout_cannot_replace_an_accessible_account_or_authentication_failure
    linked
    Stripe::Account.stub(:retrieve,account) {assert_raises(Accounts::Unavailable) {Accounts.replace_unavailable!(@employer)}}
    Stripe::Account.stub(:retrieve,->(*) {raise Stripe::AuthenticationError,'invalid credentials'}) {assert_raises(Accounts::Unavailable) {Accounts.replace_unavailable!(@employer)}}
    assert_equal 'acct_owner',@employer.reload.stripe_connect_account_id
    assert_equal 0,LightekPayments::ConnectionChange.count
  end
  def test_payout_http_session_is_current_owner_scoped_and_contains_no_private_api_key
    sign_in;linked
    Stripe::Account.stub(:retrieve,account) do
      Stripe::AccountSession.stub(:create,OpenStruct.new(client_secret:'fixture_session_secret')) do
        post dashboard_payout_account_session_path,params:{user_id:@other.id,account_id:'acct_other',authenticity_token:@csrf},headers:{'Origin'=>'http://example.test'}
        assert_response :success
        assert_equal 'fixture_session_secret',response.parsed_body['client_secret']
        refute_includes response.body,'sk_test'
        assert_includes response.headers['Cache-Control'], 'no-store'
        assert_includes response.headers['Cache-Control'], 'private'
      end
    end
  end
  def test_payout_status_refresh_verifies_live_state_without_exposing_provider_identifiers
    sign_in; linked
    Stripe::Account.stub(:retrieve, account) do
      get dashboard_payout_account_status_path
      assert_response :success
      assert_equal({'state'=>'ready','replaceable'=>false}, response.parsed_body)
      refute_includes response.body, 'acct_'
    end
  end
  def test_payout_http_rejects_missing_csrf_and_delegated_sessions
    sign_in
    assert_raises(ActionController::InvalidAuthenticityToken) {post dashboard_payout_account_session_path,params:{}}
    @employer.sessions.last.update!(connect_delegation:{'fixture'=>true})
    post dashboard_payout_account_session_path,params:{authenticity_token:@csrf},headers:{'Origin'=>'http://example.test'}
    assert_response :forbidden
  end
  def test_payout_clients_and_agencies_can_set_up_only_their_own_account
    %w[client white_label].each do |role|
      owner = User.create!(email_address: "#{role}@example.test", role: role)
      login(owner)
      get '/test/payout-csrf'
      csrf = response.parsed_body.fetch('token')
      Stripe::Account.stub(:create, account(owner, id: "acct_#{role}", details_submitted: false, payouts_enabled: false)) do
        Stripe::AccountSession.stub(:create, ->(values,*) {
          assert_equal "acct_#{role}", values[:account]
          OpenStruct.new(client_secret: 'fixture_session_secret')
        }) do
          post dashboard_payout_account_session_path, params: {authenticity_token: csrf}, headers: {'Origin'=>'http://example.test'}
          assert_response :success
        end
      end
      assert_equal "acct_#{role}", owner.reload.stripe_connect_account_id
      assert_nil @employer.reload.stripe_connect_account_id
    end
  end
  def test_payout_hosted_fallback_is_owner_scoped_and_rejects_untrusted_destinations
    linked
    Stripe::Account.stub(:retrieve,account) do
      Stripe::AccountLink.stub(:create,OpenStruct.new(url:'https://accounts.stripe.com/setup/fixture')) do
        assert_equal 'https://accounts.stripe.com/setup/fixture',Accounts.hosted_link!(@employer,refresh_url:'https://app.example.test/refresh',return_url:'https://app.example.test/payout')
      end
      Stripe::AccountLink.stub(:create,OpenStruct.new(url:'https://untrusted.example.test/collect')) do
        assert_raises(Accounts::Unavailable) {Accounts.hosted_link!(@employer,refresh_url:'https://app.example.test/refresh',return_url:'https://app.example.test/payout')}
      end
    end
  end
  def test_payout_page_is_provider_neutral_and_never_claims_ready_after_refresh_failure
    sign_in;linked
    Stripe::Account.stub(:retrieve,->(*) {raise inaccessible}) do
      get dashboard_susu_payout_account_path
      assert_response :success
      page=Nokogiri::HTML(response.body)
      refute_includes page.text,'Stripe'
      refute_includes page.text,'sk_live'
      assert_includes page.text,'could not verify your payout connection'
      assert_includes page.text,'Repair an unavailable connection'
      refute_equal 'Ready for payouts',page.at_css('[data-payout-badge]').text
    end
  end
end
