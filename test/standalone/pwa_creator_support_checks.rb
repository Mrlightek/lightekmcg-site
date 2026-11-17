# Actual commerce, creator payment and settlement services. Only remote payment,
# cloud and authentication/site policy boundaries use explicit test doubles.
require_relative 'commerce_hosting_test'
require Rails.root.join('app/models/lightek_pwa/launch_settings')
ActiveRecord::Schema.define do
  create_table(:posts) { |t| t.integer :site_id; t.integer :user_id; t.string :kind; t.string :visibility; t.string :audience; t.string :moderation_state; t.integer :parent_id; t.datetime :expires_at; t.json :metadata, default: {} }
  create_table(:studio_live_operations) { |t| t.string :status; t.integer :studio_project_id }
  create_table(:studio_projects) { |t| t.references :owner, polymorphic: true; t.integer :site_id }
end
class Post < ApplicationRecord
  belongs_to :site, class_name: 'DymondSite::Site'
  belongs_to :user
end
class StudioProject < ApplicationRecord
  belongs_to :owner, polymorphic: true
end
class StudioLiveOperation < ApplicationRecord
  belongs_to :studio_project
end
require Rails.root.join('db/migrate/20261117110000_create_pwa_creator_payments')
CreatePwaCreatorPayments.new.migrate(:up)
require Rails.root.join('db/migrate/20261117143500_record_creator_transfer_attempts')
RecordCreatorTransferAttempts.new.migrate(:up)
module LightekPwa
  class Policy
    class Denied < StandardError; end
    def initialize(**); end
    def authorize! = true
  end
end
module LightekPayments
  class PayoutAccounts
    def self.options = {api_key: 'test-key'}
    def self.status(*) = {state: 'ready'}
  end
end
class Stripe::Transfer
  def self.create(*) = raise('Unexpected transfer')
end
class Stripe::PaymentIntent
  def self.retrieve(*) = raise('Unexpected payment intent call')
end
%w[creator_offer creator_payment creator_earning].each { |f| require Rails.root.join("app/models/lightek_pwa/#{f}") }
%w[creator_support creator_settlement].each { |f| require Rails.root.join("app/services/lightek_pwa/#{f}") }

class PwaCreatorSupportTest < CommerceHostingTest
  CommerceHostingTest.instance_methods(false).grep(/^test_/).each { |name| undef_method(name) }
  def setup
    super
    @before = ENV.to_h.slice('LIGHTEK_CREATOR_SUPPORT_ENABLED','LIGHTEK_CREATOR_PAYOUTS_ENABLED')
    ENV['LIGHTEK_CREATOR_SUPPORT_ENABLED']='true'
    ENV['LIGHTEK_CREATOR_PAYOUTS_ENABLED']='true'
    @creator = User.create!(role: 'client', email_address: 'creator@example.com', stripe_connect_account_id: 'acct_creator')
    @supporter = User.create!(role: 'client', email_address: 'fan@example.com')
    @offer = LightekPwa::CreatorOffer.create!(site: @site, creator: @creator, monthly_cents: 500, enabled: true)
  end
  def teardown
    %w[LIGHTEK_CREATOR_SUPPORT_ENABLED LIGHTEK_CREATOR_PAYOUTS_ENABLED].each { |key| @before.key?(key) ? ENV[key]=@before[key] : ENV.delete(key) }
    super
  end
  def quote(kind: 'tip', amount: 500, post: nil)
    LightekPwa::CreatorSupport.quote(site: @site, creator: @creator, kind: kind, principal_cents: amount, post_id: post&.id)
  end
  def checkout(kind: 'tip', amount: 500, key: SecureRandom.uuid, fee: quote(kind: kind,amount: amount)[:fee_cents])
    LightekPwa::CreatorSupport.checkout!(site: @site, creator: @creator, supporter: @supporter, kind: kind, principal_cents: amount,
      accepted_fee_cents: fee, request_key: key, post_id: nil, success_url: 'https://shop.example.com/success', cancel_url: 'https://shop.example.com/cancel')
  end
  def payment(kind: 'tip')
    LightekCommerce::StripeCheckout.stub(:start!, OpenStruct.new(url: 'https://checkout.example.com/cs_1')) { checkout(kind: kind) }
    LightekPwa::CreatorPayment.last
  end
  def earning
    p=payment
    p.order.update!(payment_provider: 'stripe', payment_reference: 'cs_1', status: 'paid', paid_at: Time.current)
    LightekPwa::CreatorSupport.record!(order: p.order)
  end
  def charge(**updates)
    {'id'=>'ch_1','paid'=>true,'payment_intent'=>'pi_1','amount'=>600,'disputed'=>false,'amount_refunded'=>0,
      'balance_transaction'=>{'status'=>'available','currency'=>'usd','net'=>550,'available_on'=>1.minute.ago.to_i}}.merge(updates.stringify_keys)
  end
  def with_charge(value)
    LightekPwa::CreatorSettlement.stub(:charge_for, value) { yield }
  end
  def test_quotes_keep_principal_and_add_fees_for_free_creators
    q=quote
    assert_equal 500,q[:principal_cents]
    assert_operator q[:fee_cents], :>,0
    assert_equal 500+q[:fee_cents],q[:subtotal_cents]
    assert_operator q[:subtotal_cents], :>=,LightekCommerce::MerchantPayouts.minimum_charge_cents(500)
  end
  def test_member_cannot_quote_another_tenants_offer_or_use_a_disabled_offer
    @offer.update!(enabled:false)
    assert_raises(ActiveRecord::RecordNotFound) {quote}
    ENV['LIGHTEK_CREATOR_SUPPORT_ENABLED']='false'
    assert_raises(LightekPwa::CreatorSupport::Unavailable) {quote}
  end
  def test_monthly_price_comes_from_creator_offer
    assert_equal 500,quote(kind:'subscription', amount:1)[:principal_cents]
    assert_raises(LightekPwa::CreatorSupport::Unavailable) {quote(amount:-50)}
    assert_raises(LightekPwa::CreatorSupport::Unavailable) {quote(amount:100001)}
  end
  def test_live_gifts_require_current_creators_public_live_session
    post=Post.create!(site_id:@site.id,user_id:@creator.id,kind:'live',visibility:'public',audience:'everyone',moderation_state:'published')
    assert_raises(LightekPwa::CreatorSupport::Unavailable) {quote(kind:'gift',post:post)}
    live=StudioLiveOperation.create!(status:'live',studio_project:StudioProject.create!(owner:@creator,site_id:@site.id));post.update!(metadata:{'live_operation_id'=>live.id})
    assert_equal post.id,quote(kind:'gift',post:post)[:post_id]
    live.update!(status:'ended')
    assert_raises(LightekPwa::CreatorSupport::Unavailable) {quote(kind:'gift',post:post)}
  end
  def test_idempotent_checkout_preserves_principal_fee_and_order
    key=SecureRandom.uuid
    LightekCommerce::StripeCheckout.stub(:start!, OpenStruct.new(url:'https://checkout.example.com')) {2.times {checkout(key:key)}}
    assert_equal 1,LightekPwa::CreatorPayment.count
    assert_equal 1,LightekCommerce::Order.count
    p=LightekPwa::CreatorPayment.last
    assert_empty p.order.revenue_share_snapshot
    assert_equal 'creator_support',p.order.purpose
    assert_equal p.principal_cents+p.fee_cents,p.order.subtotal_cents
    assert_raises(LightekPwa::CreatorSupport::Unavailable) {checkout(key:key,amount:600)}
    assert_raises(LightekPwa::CreatorSupport::Unavailable) {checkout(fee:0)}
  end
  def test_pending_checkout_never_creates_earnings_or_duplicate_subscriptions
    p=payment(kind:'subscription')
    assert_raises(LightekPwa::CreatorSupport::Unavailable) {LightekPwa::CreatorSupport.record!(order:p.order)}
    assert_empty LightekPwa::CreatorEarning.all
    assert_raises(LightekPwa::CreatorSupport::Unavailable) {payment(kind:'subscription')}
  end
  def test_verified_earning_is_idempotent_and_preserves_entire_principal
    e=earning
    assert_equal e.id,LightekPwa::CreatorSupport.record!(order:e.order).id
    assert_equal 500,e.principal_cents
    assert_equal 'held',e.state
    assert_raises(LightekCommerce::MerchantPayouts::Invalid) {LightekCommerce::MerchantPayouts.request!(order:e.order,merchant:@operator)}
  end
  def test_actual_signed_payment_service_creates_earning_only_after_verification
    p=payment
    p.order.update!(payment_provider:'stripe',payment_reference:'cs_1')
    session=OpenStruct.new(id:'cs_1',metadata:LightekCommerce::PaymentIdentity.metadata(p.order),currency:'usd',mode:'payment',payment_status:'paid',amount_subtotal:p.order.subtotal_cents,
      amount_total:p.order.total_cents,total_details:OpenStruct.new(amount_tax:0,amount_shipping:0))
    event=OpenStruct.new(type:'checkout.session.completed',data:OpenStruct.new(object:session))
    2.times {LightekCommerce::StripeEvents.process!(event)}
    assert_equal 1,LightekPwa::CreatorEarning.count
    assert_equal 500,LightekPwa::CreatorEarning.last.principal_cents
  end
  def test_signed_renewals_credit_the_snapshot_principal_once
    p=payment(kind:'subscription');p.order.update!(status:'paid',paid_at:Time.current)
    register(p.order)
    LightekPwa::CreatorSupport.record!(order:p.order)
    invoice={'id'=>'in_renewal','subscription'=>'sub_1','status'=>'paid','currency'=>'usd','amount_paid'=>p.order.total_cents,
      'subtotal'=>p.order.subtotal_cents,'tax'=>0,'total'=>p.order.total_cents,'billing_reason'=>'subscription_cycle'}
    event=OpenStruct.new(type:'invoice.paid',created:Time.current.to_i,data:OpenStruct.new(object:invoice))
    Stripe::Subscription.stub(:retrieve,remote_subscription(p.order)) {2.times {LightekCommerce::SubscriptionEvents.process!(event)}}
    assert_equal [500,500],LightekPwa::CreatorEarning.order(:id).pluck(:principal_cents)
    renewal=LightekPwa::CreatorEarning.order(:id).last.order
    assert_equal 'creator_support_renewal',renewal.purpose
    assert_empty renewal.revenue_share_snapshot
    renewal.update!(status:'refunded')
    Stripe::Subscription.stub(:retrieve,remote_subscription(p.order)) {LightekCommerce::SubscriptionEvents.process!(event)}
    assert_equal 2,LightekPwa::CreatorEarning.count
  end
  def test_source_resolution_checks_real_checkout_identity_and_payment_amount
    e=earning;order=e.order
    session={'payment_status'=>'paid','metadata'=>LightekCommerce::PaymentIdentity.metadata(order).stringify_keys,'payment_intent'=>'pi_1'}
    intent={'status'=>'succeeded','currency'=>'usd','amount_received'=>order.total_cents,'latest_charge'=>charge(amount:order.total_cents)}
    Stripe::Checkout::Session.stub(:retrieve,session) do
      Stripe::PaymentIntent.stub(:retrieve,intent) {assert_equal 'ch_1',LightekPwa::CreatorSettlement.charge_for(order)['id']}
      Stripe::PaymentIntent.stub(:retrieve,intent.merge('amount_received'=>1)) {assert_raises(LightekPwa::CreatorSettlement::Unavailable) {LightekPwa::CreatorSettlement.charge_for(order)}}
    end
    Stripe::Checkout::Session.stub(:retrieve,session.merge('metadata'=>{})) {assert_raises(LightekPwa::CreatorSettlement::Unavailable) {LightekPwa::CreatorSettlement.charge_for(order)}}
  end
  def test_estimated_or_unavailable_funds_cannot_be_released
    e=earning
    with_charge(charge(balance_transaction:{'status'=>'pending','currency'=>'usd','net'=>550,'available_on'=>1.day.from_now.to_i})) do
      assert_equal 'held',LightekPwa::CreatorSettlement.refresh!(e).state
      assert_raises(LightekPwa::CreatorSettlement::Unavailable) {LightekPwa::CreatorSettlement.release!(earning:e,actor:@creator)}
    end
    with_charge(charge(balance_transaction:{'status'=>'available','currency'=>'usd','net'=>499,'available_on'=>1.minute.ago.to_i})) {assert_equal 'held',LightekPwa::CreatorSettlement.refresh!(e).state}
  end
  def test_full_principal_transfer_is_bound_to_source_charge_and_verified_creator
    e=earning;calls=[]
    with_charge(charge) do
      Stripe::Transfer.stub(:create, ->(params,opts) {calls << [params,opts];OpenStruct.new(id:'tr_1',**params)}) do
        assert_raises(LightekPwa::CreatorSettlement::Unavailable) {LightekPwa::CreatorSettlement.release!(earning:e,actor:@supporter)}
        2.times {LightekPwa::CreatorSettlement.release!(earning:e,actor:@creator)}
      end
    end
    assert_equal 1,calls.size
    assert_equal 500,calls.first[0][:amount]
    assert_equal 'ch_1',calls.first[0][:source_transaction]
    assert_equal 'transferred',e.reload.state
    refute_equal 'bank_paid',e.state
  end
  def test_uncertain_transfer_retains_destination_and_idempotency_for_recovery
    e=earning;keys=[]
    with_charge(charge) do
      Stripe::Transfer.stub(:create, ->(params,opts) {keys << opts[:idempotency_key];raise IOError,'timeout'}) do
        assert_raises(IOError) {LightekPwa::CreatorSettlement.release!(earning:e,actor:@creator)}
      end
      assert_equal 'transfer_pending',e.reload.state
      assert_equal 'acct_creator',e.destination_account
      @creator.update!(stripe_connect_account_id:'acct_other')
      assert_raises(LightekPwa::CreatorSettlement::Unavailable) {LightekPwa::CreatorSettlement.release!(earning:e,actor:@creator)}
      @creator.update!(stripe_connect_account_id:'acct_creator')
      Stripe::Transfer.stub(:create, ->(params,opts) {keys << opts[:idempotency_key];OpenStruct.new(id:'tr_1',**params)}) {LightekPwa::CreatorSettlement.release!(earning:e,actor:@creator)}
    end
    assert_equal 1,keys.uniq.size
  end
  def test_old_uncertain_support_transfer_requires_reconciliation_before_reposting
    e=earning
    e.update!(state:'transfer_pending',destination_account:'acct_creator',transfer_requested_at:2.days.ago)
    with_charge(charge) do
      Stripe::Transfer.stub(:create, ->(*) {raise 'An old uncertain transfer must never be blindly repeated'}) do
        assert_raises(LightekPwa::CreatorSettlement::Unavailable) {LightekPwa::CreatorSettlement.release!(earning:e,actor:@creator)}
      end
    end
    assert_equal 'transfer_pending',e.reload.state
  end
  def test_uncertain_reversal_keeps_the_refund_hold_durable
    e=earning;e.update!(state:'transferred',charge_reference:'ch_1',transfer_reference:'tr_1')
    with_charge(charge(amount_refunded:100)) do
      Stripe::Transfer.stub(:create_reversal, ->(*){raise IOError,'lost reversal receipt'}) {assert_raises(IOError) {LightekPwa::CreatorSettlement.refresh!(e)}}
      assert_equal 'held',e.reload.state
      assert_equal 'Refund or dispute under review',e.hold_reason
      assert_equal 'tr_1',e.transfer_reference
    end
  end
  def test_refunds_hold_and_reverse_only_the_related_creator_transfer
    e=earning;e.update!(state:'transferred',charge_reference:'ch_1',transfer_reference:'tr_1')
    calls=[]
    with_charge(charge(amount_refunded:100)) do
      Stripe::Transfer.stub(:create_reversal, ->(ref,params,opts){calls << [ref,params];OpenStruct.new(id:'trr_1')}) {2.times {LightekPwa::CreatorSettlement.refresh!(e)}}
    end
    assert_equal [['tr_1',{amount:500}]],calls
    assert_equal 'reversed',e.reload.state
    assert_equal 'trr_1',e.reversal_reference
  end
end
