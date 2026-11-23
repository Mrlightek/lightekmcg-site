require_relative "commerce_hosting_test"

require Rails.root.join("db/migrate/20261123135000_create_lightek_communications_services").to_s
CreateLightekCommunicationsServices.new.migrate(:up)
ActiveRecord::Migration.add_column :lightek_commerce_subscriptions, :current_period_start, :datetime
LightekCommerce::Subscription.reset_column_information
require Rails.root.join("app/models/lightek_communications/service").to_s
require Rails.root.join("app/models/lightek_communications/service_event").to_s
require Rails.root.join("app/services/lightek_communications/fulfillment").to_s
require Rails.root.join("app/services/lightek_communications/voip_ms").to_s

class Current
  class_attribute :session
end

class CommunicationsServicesTest < CommerceHostingTest
  CommerceHostingTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }

  Fulfillment = LightekCommunications::Fulfillment
  VoipMs = LightekCommunications::VoipMs
  INTERNET_PROOF = {
    access_reference: "access-1",
    gateway_reference: "gateway-1",
    traffic_test_reference: "probe-1"
  }.freeze

  def paid_subscription(slug = "lightek-internet")
    order = order_for(product(slug: slug))
    order.update!(status: "paid", purpose: "purchase", paid_at: Time.current)
    subscription = LightekCommerce::Subscription.create!(order: order, status: "active", processor_reference: "sub_#{order.id}",
      billing_interval: "month", amount_cents: 2500, currency: "usd", current_period_start: 1.day.ago, current_period_end: 1.month.from_now)
    receipt = subscription.billing_invoices.create!(settlement_order: order, processor_reference: "in_#{order.id}",
      amount_paid_cents: 2500, currency: "usd", paid_at: Time.current)
    [order, subscription, receipt]
  end

  def test_paid_checkout_internet_lifecycle_requires_evidence_and_preserves_history
    order, subscription, receipt = paid_subscription
    assert_equal "internet", order.items.sole.purchase_snapshot["communications_kind"]
    service = Fulfillment.register!(order: order, operator: @operator)
    assert_equal service, Fulfillment.register!(order: order.reload, operator: @operator)
    assert_equal "provisioning", service.status
    assert_equal receipt, service.events.sole.billing_invoice

    assert_raises(Fulfillment::Invalid) do
      Fulfillment.transition!(service: service, action: "activate", operator: @operator, evidence: {})
    end
    Fulfillment.transition!(service: service, action: "activate", operator: @operator, evidence: INTERNET_PROOF)
    assert_equal "in_service", service.reload.status

    subscription.update!(status: "past_due")
    Fulfillment.transition!(service: service, action: "suspend", operator: @operator,
      evidence: { suspension_reference: "gateway-stop-1" })
    assert_equal "suspended", service.reload.status
    assert_raises(Fulfillment::Invalid) do
      Fulfillment.transition!(service: service, action: "restore", operator: @operator, evidence: INTERNET_PROOF)
    end
    subscription.update!(status: "active")
    Fulfillment.transition!(service: service, action: "restore", operator: @operator, evidence: INTERNET_PROOF)
    assert_equal %w[register activate suspend restore], service.events.order(:id).pluck(:action)
  end

  def test_rejects_old_or_refunded_receipts_and_orders_without_the_checkout_classification
    order, subscription, receipt = paid_subscription
    receipt.update!(paid_at: 2.days.ago)
    assert_nil Fulfillment.billing_receipt(subscription)
    receipt.update!(paid_at: Time.current)
    order.update!(status: "refunded")
    assert_nil Fulfillment.billing_receipt(subscription.reload)
    order.update!(status: "paid")
    order.items.sole.update!(purchase_snapshot: { "product_type" => "service", "billing_interval" => "month" })
    assert_raises(Fulfillment::Invalid) { Fulfillment.register!(order: order, operator: @operator) }
  end

  def test_ambiguous_accounts_and_delegated_or_nonplatform_operators_cannot_provision
    order, = paid_subscription
    client = User.create!(role: "admin", email_address: "admin@example.test")
    assert_raises(Fulfillment::Invalid) { Fulfillment.register!(order: order, operator: client) }

    Current.session = Struct.new(:connect_delegation).new({ "delegated" => true })
    assert_raises(Fulfillment::Invalid) { Fulfillment.register!(order: order, operator: @operator) }
  ensure
    Current.session = nil
  end

  def test_voice_needs_carrier_verification_before_recording_activation
    order, = paid_subscription("lightek-voice")
    service = Fulfillment.register!(order: order, operator: @operator)
    proof = { sip_account: "123456_pbx", phone_number: "+12125550123", carrier_reference: "carrier-order-1",
      inbound_test_reference: "test-in", outbound_test_reference: "test-out", emergency_test_reference: "test-emergency" }

    VoipMs.stub(:verify!, ->(**) { raise VoipMs::Unavailable, "Routing mismatch" }) do
      assert_raises(VoipMs::Unavailable) do
        Fulfillment.transition!(service: service, action: "activate", operator: @operator, evidence: proof)
      end
      assert_equal "provisioning", service.reload.status
      assert_equal 1, service.events.count
    end
    VoipMs.stub(:verify!, { "carrier" => "voip_ms" }) do
      Fulfillment.transition!(service: service, action: "activate", operator: @operator, evidence: proof)
    end
    assert_equal "voip_ms", service.events.find_by!(action: "activate").evidence.fetch("carrier")
  end

  def test_voip_ms_checks_the_exact_number_route_and_registration
    carrier = VoipMs.new({})
    calls = []
    carrier.define_singleton_method(:fetch!) do |method, **parameters|
      calls << [method, parameters]
      if method == "getDIDsInfo"
        { "dids" => [{ "did" => "2125550123", "routing" => "account:123456_pbx" }] }
      else
        { "registered" => "yes" }
      end
    end
    assert_equal "voip_ms", carrier.verify!(account: "123456_pbx", phone_number: "+12125550123").fetch("carrier")
    assert_equal [["getDIDsInfo", { did: "2125550123" }], ["getRegistrationStatus", { account: "123456_pbx" }]], calls
    assert_raises(VoipMs::Unavailable) { carrier.verify!(account: "123456_other", phone_number: "+12125550123") }
    calls.clear
    carrier.verify!(account: "123456_pbx")
    assert_equal [["getRegistrationStatus", { account: "123456_pbx" }]], calls
  end
end
