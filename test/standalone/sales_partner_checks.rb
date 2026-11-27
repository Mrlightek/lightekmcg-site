# Run through the existing hosted form, CRM, catalog quotes and Commerce settlement.
require_relative 'growth_foundation_checks'
require ROOT.join('app/helpers/nevaeh_help_helper')
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
