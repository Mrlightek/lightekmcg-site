# Run through the existing hosted form, CRM, catalog quotes and Commerce settlement.
require_relative 'growth_foundation_checks'
require ROOT.join('app/helpers/nevaeh_help_helper')
require ROOT.join('app/services/lightek_sales/commission_disbursements')
require ROOT.join('app/jobs/lightek_sales/commission_payout_reconciliation_job')
require 'minitest/mock'
require ROOT.join('app/controllers/dashboard/sales_partners_controller')
Dashboard::SalesPartnersController.prepend_view_path ROOT.join('app/views')
Dashboard::SalesPartnersController.layout false

class SalesPartnerChecks < GrowthFoundationChecks
  def self.runnable_methods = instance_methods.grep(/^test_partner_/).map(&:to_s)

  def setup
    super
    @product = offer
    @partner = LightekSales::Partner.create!(site: @site, product: @product, name: 'Local referral business',
      agreement_reference: 'signed-referral-1', commission_cents: 5_000)
  end

  def run
    DymondBank::WorkforcePayouts.stub(:configured?, false) { super }
  end

  def native_inquiry(code: @partner.referral_code, host: @site.host, email: 'buyer@example.test')
    host! host
    https!
    get sales_inquiry_path(ref: code)
    assert_response :success
    form = Nokogiri::HTML(response.body).at_css('form')
    post form['action'], params: {authenticity_token: form.at_css('input[name="authenticity_token"]')['value'],
      sales_submission: {name: 'Partner buyer', email: email, company: 'Buyer Co', message: 'Can we see a demo?'}}
    assert_redirected_to sales_inquiry_path
    inquiry = WebsiteTemplateInquiry.last
    follow_redirect!
    assert_select 'h1', 'Inquiry received'
    inquiry
  end

  def referred_order
    prospect = process(native_inquiry)
    prospect.update!(status: 'qualified')
    deal_record = @workspace.convert!(prospect.id, {name: 'Website package', amount: '250.00',
      currency: 'USD', close_on: Date.current}, lock_version: prospect.lock_version)
    quote = issued(product: @product, opportunity: deal_record)
    LightekSales::Quotes.accept!(quote: quote, name: 'Partner buyer', reference: 'Customer approval', actor: @owner)
    [LightekSales::Referral.find_by!(lead: prospect), quote.reload.order]
  end

  def test_partner_order_funding_payout_receipt_and_refund_review
    referral, order = referred_order
    assert_equal 'Awaiting payment', referral.payout_status(referral.first_paid_order)
    assert_equal 5_000, referral.commission_cents
    assert_raises(ArgumentError) { referral.record_payout!(actor: @owner, reference: 'payout-1', expected_order_id: order.id) }

    settle(order)
    assert_equal 'Awaiting fulfillment', referral.payout_status(referral.first_paid_order)
    LightekCommerce::Fulfillment.complete!(order: order, reference: 'DELIVERED-1')
    assert_equal 'Awaiting merchant proceeds', referral.payout_status(referral.first_paid_order)
    order.update!(merchant_transfer_ref: 'tr_test', merchant_transfer_amount_cents: 4_999)
    assert_equal 'Insufficient merchant proceeds', referral.payout_status(referral.first_paid_order)
    order.update!(merchant_transfer_amount_cents: 20_000)

    refund = order.refunds.create!(status: 'pending', amount_cents: 1_000, idempotency_key: 'refund-test')
    assert_equal 'Refund review', referral.payout_status(referral.first_paid_order)
    refund.update!(status: 'failed')
    assert_equal 'Ready to record', referral.payout_status(referral.first_paid_order)
    assert_raises(ArgumentError) { referral.record_payout!(actor: @owner, reference: 'payout-1', expected_order_id: order.id + 1) }

    get dashboard_sales_partners_path(site_id: @site.id), headers: headers
    assert_response :success
    assert_includes response.body, 'Ready to record'
    path = record_dashboard_sales_commission_path(site_id: @site.id, id: referral.id)
    receipt = {receipt: {confirmed: '1', order_id: order.id, reference: 'payout-1'}}
    refute referral.reload.paid_at?
    assert_raises(ActiveRecord::RecordNotFound) do
      post path, params: receipt, headers: headers(@member).merge('X-CSRF-Token' => token(@member))
    end
    assert_raises(ActionController::InvalidAuthenticityToken) { post path, params: receipt, headers: headers }
    2.times do
      post path, params: receipt, headers: headers.merge('X-CSRF-Token' => token)
      assert_response :see_other
    end
    assert_equal order.id, referral.reload.order_id
    assert_equal 'payout-1', referral.payout_reference
    assert_equal @owner.id, referral.recorded_by_id
    assert_equal 1, LightekSales::Referral.where.not(paid_at: nil).count
    order.update!(status: 'partially_refunded', refunded_cents: 1_000)
    assert_equal 'Paid · refund review', referral.payout_status(referral.first_paid_order)
    assert_equal 'payout-1', referral.reload.payout_reference
  end

  def test_partner_link_is_site_scoped_revocable_and_only_credits_new_leads
    assert_nil native_inquiry(host: @foreign_site.host).sales_partner_id
    inquiry = native_inquiry
    assert_equal @partner.id, inquiry.sales_partner_id
    assert_equal 'partner_referral', process(inquiry).source
    duplicate = native_inquiry(email: 'BUYER@example.test')
    assert_equal process(inquiry).id, process(duplicate).id
    assert_equal 1, @partner.referrals.count

    @partner.update!(revoked_at: Time.current)
    assert_nil native_inquiry(email: 'new@example.test').sales_partner_id
    assert_equal @partner.id, inquiry.reload.sales_partner_id
    assert_equal 1, @partner.referrals.count
  end

  def test_partner_dashboard_requires_ownership_and_uses_the_repository_kit
    path = dashboard_sales_partners_path(site_id: @site.id)
    assert_raises(ActiveRecord::RecordNotFound) { get path, headers: headers(@member) }
    assert_raises(ActiveRecord::RecordNotFound) { get path, headers: headers(@other) }
    get path, headers: headers
    assert_response :success
    assert_includes response.body, @partner.referral_code
    target = Rails.root.join('docs/sales/managed-website-sales-kit.md')
    FileUtils.mkdir_p(target.dirname)
    FileUtils.cp(ROOT.join('docs/sales/managed-website-sales-kit.md'), target)
    get dashboard_sales_materials_path(site_id: @site.id), headers: headers(@member)
    assert_response :success
    assert_select 'h1', 'Lightek Sales & Marketing Kit'
    refute_includes response.body, @partner.referral_code
  end

  def test_partner_registration_rejects_foreign_products_and_owner_can_revoke
    path = dashboard_sales_partners_path(site_id: @site.id)
    foreign = offer(site: @foreign_site)
    fields = {name: 'Local design studio', agreement_reference: 'agreement-2', commission: '19.99'}
    assert_raises(ActiveRecord::RecordNotFound) do
      post path, params: {partner: fields.merge(product_id: foreign.id)}, headers: headers.merge('X-CSRF-Token' => token)
    end
    assert_equal 1, LightekSales::Partner.count
    post path, params: {partner: fields.merge(product_id: @product.id)}, headers: headers.merge('X-CSRF-Token' => token)
    assert_redirected_to path
    partner = LightekSales::Partner.last
    assert_equal 1_999, partner.commission_cents
    assert_equal @product.id, partner.product_id

    revoke_path = revoke_dashboard_sales_partner_path(site_id: @site.id, id: partner.id)
    post revoke_path, headers: headers.merge('X-CSRF-Token' => token)
    assert_redirected_to path
    assert partner.reload.revoked_at?
  end
end

class SalesPartnerDisbursementChecks < SalesPartnerChecks
  def self.runnable_methods = instance_methods.grep(/^test_partner_disbursement_/).map(&:to_s)

  class Provider
    attr_accessor :result, :live, :debit, :fail_prepare, :lose_release_response
    attr_reader :prepare_count, :release_count

    def initialize
      @prepare_count = @release_count = 0
      @debit, @live = 5_100, true
    end

    def partner_sender = {sender_ref: 'fa_sales', live: live}

    def partner_recipient!(reference:, email:)
      return if reference == 'acct_partner' && email == 'partner@example.test'

      raise DymondBank::WorkforcePayouts::Unavailable, 'Unverified recipient'
    end

    def prepare_partner_commission!(payout)
      @prepare_count += 1
      self.result ||= {
        'id' => 'poi_commission', 'livemode' => live, 'metadata' => payout.provider_metadata,
        'amount' => {'value' => payout.amount_cents, 'currency' => 'usd'},
        'from' => {'financial_account' => payout.sender_ref, 'debited' => {'value' => debit, 'currency' => 'usd'}},
        'to' => {'recipient' => payout.recipient_ref, 'credited' => {'value' => payout.amount_cents, 'currency' => 'usd'}},
        'estimated_fees' => [], 'status' => 'requires_action',
        'next_action' => {'type' => 'confirm', 'confirm' => {'reason' => 'manually_requested'}}
      }
      raise DymondBank::WorkforcePayouts::ProviderError, 'Response lost' if fail_prepare

      result.deep_dup
    end

    def retrieve!(_reference) = result.deep_dup

    def release_partner_commission!(_payout)
      @release_count += 1
      result['status'] = 'processing'
      raise DymondBank::WorkforcePayouts::ProviderError, 'Response lost' if lose_release_response

      retrieve!(nil)
    end
  end

  def setup
    super
    @provider = Provider.new
    @service = LightekSales::CommissionDisbursements.new(actor: @owner, site: @site, adapter: @provider)
    @credit, @order = referred_order
    settle(@order)
    LightekCommerce::Fulfillment.complete!(order: @order, reference: 'FULFILLED')
    @order.update!(merchant_transfer_ref: 'tr_sales', merchant_transfer_amount_cents: 20_000)
  end

  def link_recipient
    @service.link_recipient!(partner: @partner, email: 'PARTNER@example.test', reference: 'acct_partner')
  end

  def prepare
    @service.prepare!(referral: @credit, order_id: @order.id)
    @credit.reload.commission_payout
  end

  def release(payout, proceeds_cleared: true, digest: payout.review_digest)
    @service.release!(payout: payout, review_digest: digest, proceeds_cleared: proceeds_cleared)
  end

  def test_partner_disbursement_dashboard_release_and_posted_receipt
    path = link_dashboard_sales_partner_recipient_path(site_id: @site.id, id: @partner.id)
    recipient = {recipient: {email: 'partner@example.test', reference: 'acct_partner'}}
    DymondBank::WorkforcePayouts.stub(:new, @provider) do
      assert_raises(ActiveRecord::RecordNotFound) do
        post path, params: recipient, headers: headers(@member).merge('X-CSRF-Token' => token(@member))
      end
      assert_raises(ActionController::InvalidAuthenticityToken) { post path, params: recipient, headers: headers }
      post path, params: recipient, headers: headers.merge('X-CSRF-Token' => token)
      assert_response :see_other
      prepare_path = prepare_dashboard_sales_commission_path(site_id: @site.id, id: @credit.id)
      2.times do
        post prepare_path, params: {order_id: @order.id}, headers: headers.merge('X-CSRF-Token' => token)
        assert_response :see_other
      end
      assert_equal 1, @provider.prepare_count
      payout = @credit.reload.commission_payout
      get dashboard_sales_partners_path(site_id: @site.id), headers: headers
      assert_response :success
      assert_includes response.body, 'Release commission'
      assert_includes response.body, '$51.00'
      refute_includes response.body, 'Record receipt'
      release_path = release_dashboard_sales_commission_payout_path(site_id: @site.id, id: payout.id)
      review = {review_digest: payout.review_digest, proceeds_cleared: '1'}
      2.times do
        post release_path, params: review, headers: headers.merge('X-CSRF-Token' => token)
        assert_response :see_other
      end
      assert_equal 1, @provider.release_count
      assert_equal 'processing', payout.reload.state
      refute @credit.reload.paid_at?
      @provider.result.merge!('status' => 'posted', 'outbound_status' => 'posted')
      LightekSales::CommissionPayoutReconciliationJob.perform_now(payout.id)
      assert_equal 'posted', payout.reload.state
      assert_equal 'poi_commission', @credit.reload.payout_reference
      @provider.result.merge!('outbound_status' => 'returned')
      @service.refresh!(payout: payout)
      assert_equal 'returned', payout.reload.state
      assert_equal 'poi_commission', @credit.reload.payout_reference
    end
  end

  def test_partner_disbursement_stale_quote_refunds_and_fee_overrun_block_release
    assert_raises(LightekSales::CommissionDisbursements::Invalid) { prepare }
    assert_nil @credit.reload.commission_payout
    link_recipient
    payout = prepare
    assert_raises(LightekSales::CommissionDisbursements::Invalid) { release(payout, proceeds_cleared: false) }
    old_digest = payout.review_digest
    @provider.result['from']['debited']['value'] = 20_001
    assert_equal :quote_changed, release(payout, digest: old_digest)
    assert_raises(LightekSales::CommissionDisbursements::Invalid) { release(payout.reload) }
    @provider.result['from']['debited']['value'] = 5_100
    @service.refresh!(payout: payout)
    @order.update!(status: 'partially_refunded', refunded_cents: 10)
    assert_raises(LightekSales::CommissionDisbursements::Invalid) { release(payout.reload) }
    assert_equal 0, @provider.release_count
    assert_raises(ArgumentError) { @credit.record_payout!(actor: @owner, reference: 'alternate', expected_order_id: @order.id) }
  end

  def test_partner_disbursement_uncertain_attempt_requires_matching_provider_reconciliation
    link_recipient
    @provider.fail_prepare = true
    assert_raises(DymondBank::WorkforcePayouts::ProviderError) { prepare }
    payout = @credit.reload.commission_payout
    refute payout.provider_ref?
    payout.update_columns(created_at: 23.hours.ago)
    assert_raises(LightekSales::CommissionDisbursements::Invalid) { prepare }
    assert_equal 1, @provider.prepare_count

    @provider.result['metadata']['referral_id'] = 'wrong'
    assert_raises(LightekSales::CommissionDisbursements::Invalid) do
      @service.refresh!(payout: payout, reference: 'poi_commission')
    end
    @provider.result['metadata'] = payout.provider_metadata
    @service.refresh!(payout: payout, reference: 'poi_commission')
    @provider.lose_release_response = true
    assert_raises(DymondBank::WorkforcePayouts::ProviderError) { release(payout.reload) }
    assert_equal 'confirming', payout.reload.state
    assert payout.release_attempted_at?
    release(payout)
    assert_equal 1, @provider.release_count
    assert_equal 'processing', payout.reload.state
  end

  def test_partner_disbursement_dymond_bank_request_uses_sender_recipient_and_stable_keys
    link_recipient
    payout = prepare
    calls = []
    adapter = Class.new(DymondBank::WorkforcePayouts) do
      attr_accessor :calls

      def request(method, path, body = nil, key: nil)
        calls << [method, path, body, key]
        {}
      end
    end.new(employer: @owner)
    adapter.calls = calls
    adapter.prepare_partner_commission!(payout)
    adapter.release_partner_commission!(payout)
    assert_equal :post, calls[0][0]
    assert_equal '/v2/money_management/payout_intents', calls[0][1]
    assert_equal({'financial_account' => 'fa_sales', 'currency' => 'usd'}, calls[0][2]['from'])
    assert_equal 'acct_partner', calls[0][2].dig('to', 'recipient')
    assert_equal({'value' => 5_000, 'currency' => 'usd'}, calls[0][2]['amount'])
    assert_equal 'manual', calls[0][2]['confirmation_method']
    assert_equal payout.provider_metadata, calls[0][2]['metadata']
    assert_equal "sales-commission-#{payout.id}-prepare-v1", calls[0][3]
    assert_equal [:post, '/v2/money_management/payout_intents/poi_commission/confirm', {},
      "sales-commission-#{payout.id}-confirm-v1"], calls[1]
  end

  def test_partner_disbursement_sandbox_cannot_write_a_live_receipt
    @provider.live = false
    link_recipient
    payout = prepare
    release(payout)
    @provider.result.merge!('status' => 'posted', 'outbound_status' => 'posted')
    @service.refresh!(payout: payout)
    assert_equal 'sandbox_posted', payout.reload.state
    refute @credit.reload.paid_at?
  end
end

require ROOT.join('app/services/lightek_sales/partner_payout_onboarding')
require ROOT.join('app/controllers/sales_partner_payouts_controller')
SalesPartnerPayoutsController.prepend_view_path ROOT.join('app/views')
SalesPartnerPayoutsController.layout false
class SalesPartnerPayoutsController
  skip_before_action :require_settings_operator!
  helper_method :authentication_branding
  def authentication_branding = OpenStruct.new(name: 'Lightek Test', logo_url: nil, platform?: true)
end
class Current < ActiveSupport::CurrentAttributes
  attribute :session
end unless defined?(Current)

class SalesPartnerOnboardingChecks < SalesPartnerChecks
  def self.runnable_methods = instance_methods.grep(/^test_partner_onboarding_/).map(&:to_s)

  class Provider
    attr_accessor :active, :timeout, :sender
    attr_reader :created, :linked

    def initialize
      @created, @linked = [], []
      @sender = 'fa_commission'
    end

    def partner_sender = {sender_ref: sender, live: false}

    def create_partner_recipient!(partner)
      @created << [partner.payout_email, partner.payout_entity_type, partner.referral_code]
      raise DymondBank::WorkforcePayouts::ProviderError, 'Provider timeout' if timeout

      'acct_payoutrecipient'
    end

    def partner_recipient!(reference:, email:)
      unless active && reference == 'acct_payoutrecipient' && email == 'sales@example.test'
        raise DymondBank::WorkforcePayouts::Unavailable, 'Recipient is pending'
      end
    end

    def partner_onboarding_link!(**args)
      @linked << args
      'https://connect.stripe.com/setup/fixture'
    end
  end

  def setup
    super
    LightekSales::Partner.generated_token_verifier ||= ActiveSupport::MessageVerifier.new('test-only-signing-secret')
    @partner.update!(payout_email: @member.email_address, payout_invited_by: @owner)
    @invite = @partner.generate_token_for(:payout_setup)
    @provider = Provider.new
  end

  def onboarding(actor: @member, invite: @invite)
    LightekSales::PartnerPayoutOnboarding.new(actor: actor, partner: @partner.reload, token: invite, adapter: @provider)
  end

  def start(service = onboarding, entity_type: 'company')
    service.start!(return_url: 'https://lightek.test/payouts', refresh_url: 'https://lightek.test/payouts',
      entity_type: entity_type)
  end

  def test_partner_onboarding_http_creates_links_and_reports_active
    host! @site.host
    https!
    path = sales_partner_payout_setup_path(id: @partner.id)
    DymondBank::WorkforcePayouts.stub(:new, @provider) do
      assert_raises(ActiveRecord::RecordNotFound) do
        get sales_partner_payout_setup_path(id: @partner.id, setup_token: @invite), headers: headers(@other)
      end
      get sales_partner_payout_setup_path(id: @partner.id, setup_token: @invite), headers: headers(@member)
      assert_response :success
      assert_equal 'no-referrer', response.headers['Referrer-Policy']
      assert_select 'h1', 'Set up commission payouts'
      assert_raises(ActionController::InvalidAuthenticityToken) do
        post path, params: {setup_token: @invite, entity_type: 'company'}, headers: headers(@member)
      end
      post path, params: {setup_token: @invite, entity_type: 'company'},
        headers: headers(@member).merge('X-CSRF-Token' => token(@member))
      assert_redirected_to 'https://connect.stripe.com/setup/fixture'
      assert_equal @member.id, @partner.reload.payout_user_id
      assert_equal 'acct_payoutrecipient', @partner.payout_recipient_ref
      assert_equal @site.host, URI.parse(@provider.linked.last.fetch(:return_url)).host
      refute_includes @provider.linked.last.fetch(:return_url), @invite

      post path, headers: headers(@member).merge('X-CSRF-Token' => token(@member))
      assert_redirected_to 'https://connect.stripe.com/setup/fixture'
      assert_equal 1, @provider.created.length
      @provider.active = true
      get path, headers: headers(@member)
      assert_response :success
      assert_select '[role="status"]', /ready to receive/
    end
  end

  def test_partner_onboarding_first_attempt_is_durable_and_replays_same_recipient
    @provider.timeout = true
    assert_raises(DymondBank::WorkforcePayouts::ProviderError) { start }
    assert @partner.reload.payout_setup_started_at?
    assert_equal @member.id, @partner.payout_user_id
    refute @partner.payout_recipient_ref?
    @provider.timeout = false
    assert_equal 'https://connect.stripe.com/setup/fixture', start(onboarding(invite: nil), entity_type: 'individual')
    assert_equal [@provider.created.first] * 2, @provider.created
    @provider.sender = 'fa_wrong_sender'
    assert_raises(LightekSales::PartnerPayoutOnboarding::Invalid) { start(onboarding(invite: nil)) }
    @partner.update!(revoked_at: Time.current)
    assert_raises(ActiveRecord::RecordNotFound) { start(onboarding(invite: nil)) }
  end
end
