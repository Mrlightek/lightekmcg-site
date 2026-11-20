require_relative 'commerce_hosting_test'

ActiveRecord::Schema.define do
  add_column :users, :access_suspended_at, :datetime
  create_table(:lightek_agency_demos) { |t| t.references :site }
end
require Rails.root.join('db/migrate/20261120190000_create_lightek_agency_trials').to_s
CreateLightekAgencyTrials.new.migrate(:up)
require Rails.root.join('db/migrate/20261120200000_create_lightek_agency_trial_requests').to_s
CreateLightekAgencyTrialRequests.new.migrate(:up)
require Rails.root.join('db/migrate/20261120210000_add_business_type_to_agency_demos').to_s
AddBusinessTypeToAgencyDemos.new.migrate(:up)

require Rails.root.join('app/models/lightek_agency/demo').to_s
require Rails.root.join('app/services/lightek_agency/demos').to_s
require Rails.root.join('app/models/lightek_agency/trial').to_s

class ApplicationJob
  def self.queue_as(*) = nil
  def self.set(*) = self
  def self.perform_later(*) = nil
end
require Rails.root.join('app/jobs/lightek_agency/membership_expiry_job').to_s

class AgencyTrialMembershipChecks < CommerceHostingTest
  CommerceHostingTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }

  def invite(site: @site, email: 'nia@example.test')
    LightekAgency::Trial.invite!(operator: @operator, billing_site: site, duration_days: 3,
      brand_name: 'Northside Media', identity: {first_name: 'Nia', last_name: 'Jones', email_address: email})
  end

  def subscription_data(order, period_end: 1.year.from_now)
    remote_subscription(order).tap do |data|
      item = data.fetch('items').fetch('data').sole
      item['current_period_end'] = period_end.to_i
      item['price']['recurring']['interval'] = 'year'
    end
  end

  def checkout_event(order, payment_status: 'paid', checkout_id: 'cs_agency', subscription_id: 'sub_agency')
    OpenStruct.new(type: 'checkout.session.completed', data: OpenStruct.new(object: OpenStruct.new(
      id: checkout_id, metadata: LightekCommerce::PaymentIdentity.metadata(order), mode: 'subscription',
      payment_status: payment_status, subscription: subscription_id, currency: 'usd', amount_subtotal: order.subtotal_cents,
      amount_total: order.total_cents, total_details: OpenStruct.new(amount_tax: 0, amount_shipping: 0))))
  end

  def test_invitation_and_pending_checkout_keep_the_prospect_unprivileged
    trial = invite
    assert trial.preview_open?
    assert trial.prospect.password_setup_required?
    assert_equal 'client', trial.prospect.role
    assert_nil trial.prospect.agency_profile

    order = trial.reserve_order!
    assert_equal order.id, trial.reserve_order!.id
    assert_equal trial.prospect_id, order.hosting_owner_id
    assert_equal 'agency_membership', order.purpose
    assert_equal 20_000, order.total_cents
    assert_equal 'year', order.items.sole.purchase_snapshot['billing_interval']
    assert_equal 'service', order.items.sole.product.product_type
    refute order.items.sole.product.published?
    order.update!(payment_reference: 'cs_agency')
    LightekCommerce::StripeEvents.process!(checkout_event(order, payment_status: 'unpaid'))
    assert_equal 'client', trial.prospect.reload.role
    assert_nil trial.reload.paid_through
  end

  def test_price_updates_apply_to_new_orders_and_preserve_existing_checkout_amounts
    trial = invite
    order = trial.reserve_order!(expected_price_cents: 20_000)

    %w[0.49 250.001 -1].each do |invalid|
      assert_raises(LightekAgency::Trial::Invalid) { LightekAgency::Trial.set_annual_price!(@site, dollars: invalid) }
    end
    LightekAgency::Trial.set_annual_price!(@site, dollars: '249.50')
    assert_equal 24_950, LightekAgency::Trial.annual_price_cents(@site)
    assert_equal 20_000, trial.checkout_price_cents
    assert_equal order.id, trial.reserve_order!(expected_price_cents: 20_000).id

    next_trial = invite(email: 'second@example.test')
    assert_raises(LightekAgency::Trial::Invalid) { next_trial.reserve_order!(expected_price_cents: 20_000) }
    assert_nil next_trial.reload.order
    next_order = next_trial.reserve_order!(expected_price_cents: 24_950)
    assert_equal 24_950, next_order.subtotal_cents
    assert_equal 24_950, next_order.items.sole.unit_price_cents

    order.update!(payment_reference: 'cs_agency')
    Stripe::Subscription.stub(:retrieve, subscription_data(order)) do
      LightekCommerce::StripeEvents.process!(checkout_event(order))
    end
    assert trial.reload.paid_access?
    assert_equal 20_000, order.reload.commerce_subscription.amount_cents

    next_order.update!(payment_reference: 'cs_agency_next')
    Stripe::Subscription.stub(:retrieve, subscription_data(next_order)) do
      LightekCommerce::StripeEvents.process!(checkout_event(next_order, checkout_id: 'cs_agency_next', subscription_id: 'sub_agency_next'))
    end
    assert next_trial.reload.paid_access?
    assert_equal 24_950, next_order.reload.commerce_subscription.amount_cents
  end

  def test_purchase_activates_the_same_user_and_replay_creates_one_profile
    trial = invite
    trial.update!(brand_name: 'Northside Creative')
    order = trial.reserve_order!
    order.update!(payment_reference: 'cs_agency')
    Stripe::Subscription.stub(:retrieve, subscription_data(order)) do
      2.times { LightekCommerce::StripeEvents.process!(checkout_event(order)) }
    end

    assert trial.reload.paid_access?
    refute trial.preview_open?
    assert_equal 'white_label', trial.prospect.reload.role
    assert_equal 'fulfilled', order.reload.status
    assert_equal @operator.id, trial.prospect.agency_id
    assert_equal 'Northside Creative', trial.prospect.agency_profile.brand_name
    assert_equal 1, AgencyProfile.where(user: trial.prospect).count
    assert_equal 1, LightekCommerce::Subscription.count
  end

  def test_renewal_extends_access_and_a_stale_expiry_job_leaves_it_active
    trial = invite
    order = trial.reserve_order!
    order.update!(payment_reference: 'cs_agency')
    Stripe::Subscription.stub(:retrieve, subscription_data(order)) do
      LightekCommerce::StripeEvents.process!(checkout_event(order))
    end
    original_end = trial.reload.paid_through
    LightekAgency::Trial.set_annual_price!(@site, dollars: '300')
    start_of_renewal = original_end + 1.minute
    invoice = {'id' => 'in_agency_renewal', 'subscription' => 'sub_agency', 'status' => 'paid', 'currency' => 'usd',
      'amount_paid' => 20_000, 'subtotal' => 20_000, 'tax' => 0, 'total' => 20_000, 'billing_reason' => 'subscription_cycle'}
    event = OpenStruct.new(type: 'invoice.paid', created: start_of_renewal.to_i, data: OpenStruct.new(object: invoice))
    Stripe::Subscription.stub(:retrieve, subscription_data(order, period_end: start_of_renewal.advance(years: 1))) do
      2.times { LightekCommerce::StripeEvents.process!(event) }
    end
    assert_operator trial.reload.paid_through, :>, original_end + 11.months
    assert_equal 1, LightekCommerce::BillingInvoice.count
    assert_equal 'agency_membership', trial.paid_order.purpose
    assert_equal 20_000, trial.paid_order.subtotal_cents
    assert LightekCommerce::MerchantPayouts.ineligible_reason(trial.paid_order)
    LightekAgency::MembershipExpiryJob.new.perform(trial.id)
    assert_equal 'white_label', trial.prospect.reload.role

    trial.update!(paid_through: 1.minute.ago)
    LightekAgency::MembershipExpiryJob.new.perform(trial.id)
    assert_equal 'client', trial.prospect.reload.role
    assert_equal 'Northside Media', trial.prospect.agency_profile.brand_name
  end

  def test_an_expired_demo_can_upgrade_and_a_refunded_term_loses_agency_access
    trial = invite
    trial.update!(expires_at: 1.day.ago)
    refute trial.preview_open?

    order = trial.reserve_order!
    order.update!(payment_reference: 'cs_agency')
    Stripe::Subscription.stub(:retrieve, subscription_data(order)) do
      LightekCommerce::StripeEvents.process!(checkout_event(order))
    end
    assert trial.reload.paid_access?
    order.update!(status: 'refunded', refunded_cents: order.total_cents)
    refute trial.reload.paid_access?

    LightekAgency::MembershipExpiryJob.new.perform
    assert_equal 'client', trial.prospect.reload.role
  end

  def test_private_trial_requires_an_operator_owned_storefront
    foreign = User.create!(role: 'white_label', email_address: 'other@example.test')
    foreign_site = DymondSite::Site.create!(tenant: foreign, host: 'other.example.test')
    assert_raises(ActiveRecord::RecordNotFound) { invite(site: foreign_site) }
    refute User.exists?(email_address: 'nia@example.test')
  end
end
