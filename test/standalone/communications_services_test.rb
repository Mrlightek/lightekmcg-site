require_relative "commerce_hosting_test"
require "active_job"

require Rails.root.join("db/migrate/20261123135000_create_lightek_communications_services").to_s
CreateLightekCommunicationsServices.new.migrate(:up)
ActiveRecord::Migration.add_column :lightek_commerce_subscriptions, :current_period_start, :datetime
LightekCommerce::Subscription.reset_column_information
require Rails.root.join("app/models/lightek_communications/service").to_s
require Rails.root.join("app/models/lightek_communications/service_event").to_s
require Rails.root.join("app/services/lightek_communications/fulfillment").to_s
require Rails.root.join("app/services/lightek_communications/voip_ms").to_s

require Rails.root.join("db/migrate/20261123140000_create_lightek_voice_add_ons").to_s
CreateLightekVoiceAddOns.new.migrate(:up)
require Rails.root.join("app/models/lightek_communications/voice_add_on").to_s
require Rails.root.join("app/services/lightek_communications/installation_voice").to_s
require Rails.root.join("app/services/lightek_people/lifecycle_access").to_s
require Rails.root.join("app/models/lightek_people/lifecycle_case").to_s

module LightekReservations
  module Federation
    class Issuer
      def self.origin = "https://shop.example.com"
    end
  end

  class Peer
    def order_id = id
    def active? = true
  end
end

require Rails.root.join("db/migrate/20261123141000_create_lightek_voice_carrier_operations").to_s
CreateLightekVoiceCarrierOperations.new.migrate(:up)
require Rails.root.join("app/models/lightek_communications/voice_carrier_operation").to_s
require Rails.root.join("app/services/lightek_communications/carrier_fulfillment").to_s

require Rails.root.join("db/migrate/20261123142000_add_automatic_voice_fulfillment").to_s
AddAutomaticVoiceFulfillment.new.migrate(:up)
LightekCommunications::VoiceAddOn.reset_column_information
require Rails.root.join("app/services/lightek_communications/asterisk_voice").to_s
require Rails.root.join("app/services/lightek_communications/managed_voice_trunk").to_s
require Rails.root.join("app/services/lightek_communications/voice_setup").to_s
require Rails.root.join("app/services/lightek_communications/automatic_voice_fulfillment").to_s

require Rails.root.join("app/jobs/application_job").to_s
require Rails.root.join("app/jobs/lightek_communications/voice_provisioning_job").to_s

module LightekVault
  class Secret
    def self.exists?(**) = false
  end
end

module LightekVault::Service
  def self.store!(**) = true
end

class Current
  class_attribute :session
end

class CommunicationsServicesTest < CommerceHostingTest
  CommerceHostingTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }

  Fulfillment = LightekCommunications::Fulfillment
  VoipMs = LightekCommunications::VoipMs
  VoipMs.define_singleton_method(:configured?) { true }
  INTERNET_PROOF = {
    access_reference: "access-1",
    gateway_reference: "gateway-1",
    traffic_test_reference: "probe-1"
  }.freeze

  def setup
    super
    @previous_voice_routes = ENV["LIGHTEK_VOICE_PBX_ROUTES"]
    @voice_routes = {}
  end

  def teardown
    ENV["LIGHTEK_VOICE_PBX_ROUTES"] = @previous_voice_routes
    super
  end

  def carrier_setup(port: false)
    fields = { "confirm_emergency_address" => "1", "emergency" => { "full_name" => "Business", "street_number" => "100",
      "street_name" => "Main St", "city" => "New York", "state" => "NY", "zip" => "10001" } }
    return fields unless port

    fields.merge("authorize_port" => "1", "document" => Base64.strict_encode64("%PDF-1.4"),
      "port" => { "statementName" => "Business", "firstName" => "Test", "lastName" => "Owner", "address1" => "100 Main St",
        "city" => "New York", "state" => "NY", "zip" => "10001", "providerName" => "Carrier", "providerAccount" => "acct", "isPartial" => "0" })
  end

  def paid_subscription(slug = "lightek-internet")
    order = order_for(product(slug: slug))
    order.update!(status: "paid", purpose: "purchase", paid_at: Time.current)
    subscription = LightekCommerce::Subscription.create!(order: order, status: "active", processor_reference: "sub_#{order.id}",
      billing_interval: "month", amount_cents: 2500, currency: "usd", current_period_start: 1.day.ago, current_period_end: 1.month.from_now)
    receipt = subscription.billing_invoices.create!(settlement_order: order, processor_reference: "in_#{order.id}",
      amount_paid_cents: 2500, currency: "usd", paid_at: Time.current)
    [order, subscription, receipt]
  end

  def test_installation_voice_uses_central_price_and_billing_identity_and_reuses_pending_order
    product(slug: "lightek-voice")
    peer = voice_peer("client")
    addon = LightekCommunications::InstallationVoice.new(peer)
    assert_equal "available", addon.status[:status]
    assert_equal 2500, addon.status[:price_cents]

    requests = []
    checkout = ->(**args) do
      requests << args
      OpenStruct.new(url: "https://checkout.stripe.com/c/pay")
    end
    LightekCommerce::StripeCheckout.stub(:start!, checkout) do
      assert_equal "https://checkout.stripe.com/c/pay", addon.checkout!(number_request: {"option" => "new", "area_code" => "212"}, voice_setup: carrier_setup)[:checkout_url]
      addon.checkout!
    end
    order = requests.first.fetch(:order)
    assert_equal [order.id, order.id], requests.map { |args| args[:order].id }
    assert_equal "https://client.example.com/dashboard/voice", requests.first.fetch(:success_url)
    assert_equal peer.merchant.email_address, order.customer_email
    assert_equal "voice", order.items.sole.purchase_snapshot["communications_kind"]
    assert_equal "pending_payment", addon.status[:status]
    assert_equal "available", LightekCommunications::InstallationVoice.new(voice_peer("other")).status[:status]

    order.update!(status: "paid", paid_at: Time.current)
    assert_equal "provisioning", addon.status[:status]
    assert_raises(LightekCommunications::InstallationVoice::Unavailable) { addon.checkout! }
  end

  def test_multiple_published_voice_offers_snapshot_the_selected_plan
    product(slug: "lightek-voice-monthly")
    product(slug: "lightek-voice-annual", billing_interval: "year", price_cents: 24_000)
    product(slug: "lightek-voice-hidden", published: false)
    addon = LightekCommunications::InstallationVoice.new(voice_peer("plans"))
    choices = addon.status.fetch(:offers).to_h { |offer| [offer[:key], [offer[:billing_interval], offer[:price_cents]]] }
    assert_equal({ "lightek-voice-monthly" => ["month", 2500], "lightek-voice-annual" => ["year", 24_000] }, choices)
    assert_raises(LightekCommunications::InstallationVoice::Unavailable) { addon.checkout! }
    assert_raises(LightekCommunications::InstallationVoice::Unavailable) { addon.checkout!(plan: "lightek-voice-hidden") }
    checkout = ->(**args) { OpenStruct.new(url: "https://checkout.stripe.com/c/pay") }
    LightekCommerce::StripeCheckout.stub(:start!, checkout) do
      addon.checkout!(plan: "lightek-voice-annual", number_request: {"option" => "port", "phone_number" => "(212) 555-0123"}, voice_setup: carrier_setup(port: true))
      assert_raises(LightekCommunications::InstallationVoice::Unavailable) { addon.checkout!(plan: "lightek-voice-monthly") }
      addon.checkout!
    end
    receipt = LightekCommunications::VoiceAddOn.last.order.items.sole.purchase_snapshot
    assert_equal "lightek-voice-annual", receipt["voice_plan"]
    assert_equal({ "option" => "port", "phone_number" => "+12125550123" }, receipt["voice_number_request"])
    assert_equal({ "option" => "port", "last_four" => "0123" }, addon.status.fetch(:number_request))
    assert_raises(LightekCommunications::InstallationVoice::Unavailable) do
      addon.checkout!(number_request: { "option" => "new", "area_code" => "212" })
    end
    assert_equal "year", addon.status[:billing_interval]
    assert_equal 24_000, addon.status[:price_cents]
  end

  def test_paid_voice_number_and_e911_gate_activation
    order, = paid_subscription("lightek-voice")
    service = Fulfillment.register!(order: order, operator: @operator)
    runner = LightekCommunications::CarrierFulfillment.new(service, @operator)
    client, calls = carrier_stub
    proof = { sip_account: "123456_pbx", phone_number: "+12125550123", carrier_reference: "carrier-1",
      inbound_test_reference: "test-in", outbound_test_reference: "test-out", emergency_test_reference: "test-emergency" }
    fields = proof.merge(authorized: "1", pop: "5", billing_type: "1")
    VoipMs.stub(:for_operator, client) do
      runner.order_number!(fields)
      assert_raises(LightekCommunications::CarrierFulfillment::Invalid) { runner.order_number!(fields) }
      assert_raises(Fulfillment::Invalid) do
        Fulfillment.transition!(service: service, action: "activate", operator: @operator, evidence: proof)
      end
      runner.provision_e911!(fields.merge(full_name: "Test Business", street_number: "100", street_name: "Main St",
        city: "New York", state: "NY", zip: "10001"))
      VoipMs.stub(:verify!, { "carrier" => "voip_ms" }) do
        Fulfillment.transition!(service: service, action: "activate", operator: @operator, evidence: proof)
      end
    end
    assert_equal "in_service", service.reload.status
    assert_equal %w[orderDID getDIDsInfo e911Validate e911Provision e911Info], calls.map(&:first)
    assert_equal %w[confirmed confirmed], LightekCommunications::VoiceCarrierOperation.where(service: service).order(:id).pluck(:state)
  end

  def test_e911_address_rejection_does_not_submit_or_reserve_a_provisioning_write
    order, = paid_subscription("lightek-voice")
    service = Fulfillment.register!(order: order, operator: @operator)
    runner = LightekCommunications::CarrierFulfillment.new(service, @operator)
    client = Object.new
    client.define_singleton_method(:order_number!) { |**| { "status" => "success" } }
    client.define_singleton_method(:validate_e911!) { |**| raise VoipMs::Unavailable, "Invalid address" }
    fields = { authorized: "1", phone_number: "+12125550123", sip_account: "123456_pbx", pop: "5", billing_type: "1",
      full_name: "Test Business", street_number: "100", street_name: "Main St", city: "New York", state: "NY", zip: "10001" }
    VoipMs.stub(:for_operator, client) do
      runner.order_number!(fields)
      assert_raises(VoipMs::Unavailable) { runner.provision_e911!(fields) }
    end
    refute LightekCommunications::VoiceCarrierOperation.exists?(service: service, operation: "provision_e911")
  end

  def test_port_submission_receipt_document_status_and_routing
    order, = paid_subscription("lightek-voice")
    service = Fulfillment.register!(order: order, operator: @operator)
    runner = LightekCommunications::CarrierFulfillment.new(service, @operator)
    client, calls = carrier_stub
    fields = { authorized: "1", phone_number: "+12125550123", statementName: "Test Business", firstName: "Test",
      lastName: "Owner", address1: "100 Main St", city: "New York", state: "NY", zip: "10001", providerName: "Test Carrier",
      providerAccount: "abc", isPartial: "0", sip_account: "123456_pbx", pop: "5" }
    VoipMs.stub(:for_operator, client) do
      runner.port_number!(fields)
      runner.attach_port_file!(StringIO.new("%PDF-1.4"), fields)
      runner.refresh_port!
      runner.route_port!(fields)
    end
    port = LightekCommunications::VoiceCarrierOperation.find_by!(service: service, operation: "port_number")
    assert_equal "42", port.carrier_reference
    assert_equal "Complete", port.carrier_status
    assert_equal %w[getPortability addLNPPort addLNPFile getLNPStatus getDIDsInfo setDIDPOP setDIDRouting getDIDsInfo], calls.map(&:first)
  end

  def test_ambiguous_number_order_stays_in_review_and_is_not_replayed
    order, = paid_subscription("lightek-voice")
    service = Fulfillment.register!(order: order, operator: @operator)
    runner = LightekCommunications::CarrierFulfillment.new(service, @operator)
    count = 0
    client = Object.new
    client.define_singleton_method(:order_number!) do |**|
      count += 1
      raise LightekCommunications::VoipMs::Unavailable, "Timeout"
    end
    VoipMs.stub(:for_operator, client) do
      2.times do
        assert_raises(LightekCommunications::CarrierFulfillment::Invalid) do
          runner.order_number!(authorized: "1", phone_number: "+12125550123", sip_account: "123456_pbx", pop: "5", billing_type: "1")
        end
      end
    end
    assert_equal 1, count
    assert_equal "review", LightekCommunications::VoiceCarrierOperation.find_by!(service: service).state
  end

  def carrier_stub
    client = VoipMs.new({})
    calls = []
    client.define_singleton_method(:fetch!) do |method, **parameters|
      calls << [method, parameters]
      case method
      when "getDIDsInfo" then { "dids" => [{ "did" => "2125550123", "routing" => "account:123456_pbx" }] }
      when "e911Info" then { "info" => { "did" => "2125550123", "street_number" => "100", "street_name" => "Main St", "city" => "New York", "state" => "NY", "zip_code" => "10001" } }
      when "getPortability" then { "portable" => "yes" }
      when "searchDIDsUSA" then { "dids" => [{ "did" => "2125550123", "perminute_setup" => "1.50", "perminute_monthly" => "1.00" }] }
      when "getRegistrationStatus" then { "registered" => "yes" }
      when "addLNPPort" then { "port" => "42" }
      when "getLNPStatus" then { "post_status_description" => "Complete" }
      else { "status" => "success" }
      end
    end
    [client, calls]
  end

  def test_new_checkout_requires_a_valid_number_choice_without_creating_an_order
    product(slug: "lightek-voice")
    addon = LightekCommunications::InstallationVoice.new(voice_peer("number-choice"))
    [{}, { "option" => "new", "area_code" => "123" }, { "option" => "port", "phone_number" => "555-1234" }].each do |choice|
      assert_raises(LightekCommunications::InstallationVoice::Unavailable) { addon.checkout!(number_request: choice) }
    end
    assert_empty LightekCommunications::VoiceAddOn.all
  end

  def automatic_add_on(option)
    order, subscription, invoice = paid_subscription("lightek-voice")
    peer = voice_peer("automatic")
    choice = option == "port" ? { "option" => "port", "phone_number" => "+12125550123" } : { "option" => "new", "area_code" => "212" }
    item = order.items.sole
    item.update!(purchase_snapshot: item.purchase_snapshot.merge("voice_number_request" => choice))
    add_on = LightekCommunications::VoiceAddOn.create!(peer: peer, order: order, setup_secret_slug: "voice-setup-order-#{order.id}")
    payload = carrier_setup(port: option == "port").merge("destination" => LightekCommunications::VoiceSetup.route(peer))
    [add_on, subscription, invoice, payload]
  end

  def test_signed_checkout_handler_submits_voice_job_after_settlement
    order = order_for(product(slug: "lightek-voice"))
    order.update!(payment_provider: "stripe", payment_reference: "cs_voice")
    LightekCommunications::VoiceAddOn.create!(peer: voice_peer("settle"), order: order, setup_secret_slug: "voice-setup-order-#{order.id}")
    session = OpenStruct.new(id: "cs_voice", metadata: LightekCommerce::PaymentIdentity.metadata(order), currency: "usd",
      mode: "subscription", payment_status: "unpaid", subscription: "sub_voice", invoice: "in_voice",
      amount_subtotal: 2500, amount_total: 2500, total_details: OpenStruct.new(amount_tax: 0, amount_shipping: 0))
    event = OpenStruct.new(type: "checkout.session.completed", data: OpenStruct.new(object: session))
    enqueued = []
    LightekCommunications::VoiceProvisioningJob.stub(:perform_later, ->(id) {
      assert_equal order.id, LightekCommerce::BillingInvoice.find_by!(processor_reference: "in_voice").settlement_order_id
      enqueued << id
    }) do
      LightekCommerce::StripeEvents.process!(event)
      assert_empty enqueued
      session.payment_status = "paid"
      Stripe::Subscription.stub(:retrieve, remote_subscription(order)) do
        LightekCommerce::StripeEvents.process!(event)
      end
    end
    assert_equal [order.id], enqueued
  end

  def test_verified_payment_automatically_orders_and_configures_e911_once
    add_on, _, invoice, payload = automatic_add_on("new")
    client, calls = carrier_stub
    runner = LightekCommunications::AutomaticVoiceFulfillment
    LightekCommunications::VoiceSetup.stub(:checkout!, payload) do
      VoipMs.stub(:for_paid_voice, client) do
        invoice.update!(amount_paid_cents: 0)
        runner.call(add_on)
        assert_empty calls
        invoice.update!(amount_paid_cents: 2500)
        2.times { runner.call(add_on.reload) }
      end
    end
    assert_equal "carrier_ready", add_on.reload.fulfillment_status
    assert_equal 1, calls.count { |method, _| method == "orderDID" }
    assert_equal 1, calls.count { |method, _| method == "e911Provision" }
    service = LightekCommunications::Service.sole
    assert_equal "provisioning", service.status
    assert_nil service.events.sole.operator
  end

  def test_managed_paid_order_registers_its_trunk_and_activates_once
    add_on, _, _, payload = automatic_add_on("new")
    payload["destination"] = payload.fetch("destination").except("sip_account").merge("managed" => true)
    client, calls = carrier_stub
    pbx_changes = []
    pbx = Object.new
    pbx.define_singleton_method(:connect_number!) { |did| pbx_changes << did }
    trunk = Object.new
    trunk.define_singleton_method(:register!) { |_| { "account" => "123456_pbx" } }
    proof = { "inbound" => "PBX-IN", "outbound" => "PBX-OUT", "emergency" => "PBX-E911" }
    LightekCommunications::VoiceSetup.stub(:checkout!, payload) do
      LightekCommunications::ManagedVoiceTrunk.stub(:new, trunk) do
        LightekCommunications::AsteriskVoice.stub(:new, pbx) do
          LightekCommunications::AsteriskVoice.stub(:deployment_proof, proof) do
            VoipMs.stub(:for_paid_voice, client) do
              2.times { LightekCommunications::AutomaticVoiceFulfillment.call(add_on.reload) }
            end
          end
        end
      end
    end
    assert_equal ["2125550123"], pbx_changes
    assert_equal "carrier_ready", add_on.reload.fulfillment_status
    line = LightekCommunications::Service.sole
    assert_equal "in_service", line.status
    assert_equal "PBX-E911", line.events.find_by!(action: "activate").evidence["pbx_deployment_emergency_reference"]
    assert_equal 1, calls.count { |method, _| method == "orderDID" }
    assert_equal "10001", calls.find { |method, _| method == "e911Provision" }.last.fetch(:zip_code)
  end

  def test_voip_ms_recovers_a_subaccount_write_after_a_lost_carrier_reply
    carrier = VoipMs.new({})
    account = "123456_lt4abcdef"
    description = "Lightek Voice lt4abcdef"
    created = false
    writes = []
    carrier.define_singleton_method(:fetch!) do |method, **fields|
      case method
      when "getSubAccounts"
        raise "Wrong account" unless fields.fetch(:account) == account
        { "accounts" => created ? [{ "account" => account, "description" => description }] : [] }
      when "createSubAccount"
        writes << fields.fetch(:username)
        created = true
        raise VoipMs::Unavailable, "Lost carrier response"
      else
        raise "Unexpected carrier call"
      end
    end

    assert_raises(VoipMs::Unavailable) { carrier.ensure_subaccount!(account: account, password: "test", description: description) }
    carrier.ensure_subaccount!(account: account, password: "test", description: description)
    assert_equal ["lt4abcdef"], writes
    assert_raises(VoipMs::Unavailable) { carrier.ensure_subaccount!(account: account, password: "test", description: "different owner") }
  end

  def test_automatic_port_polls_then_routes_and_provisions_e911_without_resubmitting
    add_on, _, _, payload = automatic_add_on("port")
    client, calls = carrier_stub
    ready = false
    client.define_singleton_method(:number_on_account?) { |_| ready }
    runner = LightekCommunications::AutomaticVoiceFulfillment
    LightekCommunications::VoiceSetup.stub(:checkout!, payload) do
      VoipMs.stub(:for_paid_voice, client) do
        assert_equal :waiting_for_carrier, runner.call(add_on)
        assert_equal "port_pending", add_on.reload.fulfillment_status
        refute calls.any? { |method, _| method == "e911Provision" }
        ready = true
        runner.call(add_on.reload)
      end
    end
    assert_equal "carrier_ready", add_on.reload.fulfillment_status
    assert_equal 1, calls.count { |method, _| method == "addLNPPort" }
    assert_equal 1, calls.count { |method, _| method == "addLNPFile" }
    assert_equal 1, calls.count { |method, _| method == "setDIDRouting" }
  end

  def test_carrier_cannot_order_a_new_number_for_customer_who_requested_a_port
    order, = paid_subscription("lightek-voice")
    item = order.items.sole
    item.update!(purchase_snapshot: item.purchase_snapshot.merge(
      "voice_number_request" => { "option" => "port", "phone_number" => "+12125550123" }))
    service = Fulfillment.register!(order: order, operator: @operator)
    runner = LightekCommunications::CarrierFulfillment.new(service, @operator)
    assert_raises(LightekCommunications::CarrierFulfillment::Invalid) do
      runner.order_number!(authorized: "1", phone_number: "+12125550124", sip_account: "123456_pbx", pop: "5", billing_type: "1")
    end
    assert_empty LightekCommunications::VoiceCarrierOperation.where(service: service)
  end

  def test_installation_voice_requires_active_peer_and_rejects_untrusted_checkout_urls
    peer = voice_peer("inactive")
    peer.stub(:active?, false) do
      assert_raises(LightekCommunications::InstallationVoice::Unavailable) do
        LightekCommunications::InstallationVoice.new(peer)
      end
    end
    assert_raises(LightekCommunications::InstallationVoice::Unavailable) do
      LightekCommunications::InstallationVoice.checkout_url!("https://checkout.stripe.com@evil.example/")
    end
  end

  def voice_peer(label)
    owner = User.create!(role: "client", email_address: "#{label}@example.com")
    site = DymondSite::Site.create!(tenant: owner, host: "#{label}.example.com")
    @voice_routes[site.host] = { "sip_account" => "123456_pbx", "pop" => 5, "max_setup_cents" => 400, "max_monthly_cents" => 500 }
    ENV["LIGHTEK_VOICE_PBX_ROUTES"] = JSON.generate(@voice_routes)
    LightekReservations::Peer.create!(merchant: owner, site: site)
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
