require_relative "reservations_http_checks"
require "minitest/mock"

module ItBusinessSchema
  def self.migrate(root, filename, direction = :up)
    path = root.join("db/migrate", "#{filename}.rb")
    require path.to_s
    path.read.match(/class (\w+) </)[1].constantize.new.migrate(direction)
  end

  migrate(ROOT, "20261113160000_create_lightek_people_and_payroll")
  migrate(ROOT, "20260722102123_create_marlon_tickets")
  migrate(ROOT, "20260722102124_create_marlon_ticket_events")
  connection = ActiveRecord::Base.connection
  connection.add_column(:lightek_commerce_subscriptions, :current_period_start, :datetime)
  connection.add_column(:lightek_commerce_products, :short_description, :string)
  connection.add_column(:lightek_people_employments, :directory_principal, :string)
  %i[compliance_access accounting_access].each do |field|
    connection.add_column(:lightek_people_employments, field, :string, default: "none")
  end
  connection.create_table(:network_managed_devices)
  migrate(ROOT, "20261124170000_create_it_service_business_operations", :up)
  migrate(ROOT, "20261124170000_create_it_service_business_operations", :down)
  migrate(ROOT, "20261124170000_create_it_service_business_operations", :up)
end

class NetworkManagedDevice < ApplicationRecord; end

class User
  def access_active? = !email_address.start_with?("inactive")
end

class LightekCommerce::Product
  def communications_kind = nil
  def full_communications_package? = false
  def cellular_voice_bundle? = false
end

module DymondBank
  class Subscription < ApplicationRecord; end

  module StripeCredentials
    def self.secret_key = "sk_test_it_services"
  end
end

module NevaehCustomerService
  class Cases
    SOURCE = "nevaeh_customer_service"
  end
end

module NevaehIntelligences
  module TicketBacklog
    def self.enabled? = false
  end
end

%w[marlon/ticket_categories marlon/ticket marlon/ticket_event lightek_people/department lightek_people/employment
  lightek_people/pay_run lightek_people/pay_statement lightek_people/audit_event lightek_people/benefit_plan
  lightek_people/benefit_enrollment lightek_people/payout_destination].each do |path|
  require ROOT.join("app/models", path).to_s
end
require ROOT.join("app/controllers/concerns/lightek_identity/sensitive_session").to_s

batch_b = Pathname.new(ENV.fetch("IT_SERVICES_BATCH_B_ROOT", ROOT.to_s))
if batch_b.join("app/services/it_services/completion.rb").file?
  %w[20261123235000_create_it_service_requests 20261123235500_create_it_service_events
    20261124001000_add_it_service_device_ownership 20261124002000_add_reservation_to_it_service_requests
    20261124004000_add_technician_to_it_service_requests].each do |migration|
    ItBusinessSchema.migrate(batch_b, migration)
  end
  %w[models/it_service_request models/it_service_event services/it_services/payment_clearance
    services/it_services/reservation_assignment services/it_services/nevaeh_work_handoff services/it_services/technician_assignment
    services/it_services/appointment_dispatch services/it_services/technician_work services/it_services/technician_response
    services/it_services/completion].each do |path|
    require batch_b.join("app", path).to_s
  end
  IT_BATCH_B_REAL = true
else
  abort "Batch B source required for the integrated rehearsal" if ENV["IT_SERVICES_REQUIRE_BATCH_B"] == "1"
  puts "Batch C contract rehearsal (Batch B code is absent from this checkout)."
  ActiveRecord::Schema.define do
    create_table(:it_service_requests) do |t|
      t.references :user
      t.references :reservation
      t.references :technician
      t.string :status
      t.string :service_code
      t.string :delivery_mode
      t.string :description
      t.string :service_location
      t.datetime :technician_assigned_at
      t.datetime :closed_at
      t.timestamps
    end
  end
  ItServiceEvent = nil
  class ItServiceRequest < ApplicationRecord
    belongs_to :user
    belongs_to :reservation, class_name: "LightekReservations::Reservation", optional: true
    belongs_to :technician, class_name: "User", optional: true
  end
  module ItServices
    class PaymentClearance
      def self.verify!(request:)
        raise ArgumentError, "Service checkout required before technician dispatch" unless request.reservation.paid?

        { "source" => "lightek_reservations", "order_id" => request.reservation.order_id, "reservation_id" => request.reservation_id }
      end
    end
  end
end

%w[plan membership coverage_period coverage_claim payout settles_completed_appointments].each do |path|
  require ROOT.join("app/models/it_services", path).to_s
end
%w[it_services/enrollment it_services/invoice_coverage it_services/covered_payment_clearance
  it_services/technician_payout it_services/completed_appointment_settlement gatekeeper/it_service_billing_policy
  lightek_commerce/subscription_cancellation lightek_people/access lightek_people/payroll
  lightek_people/disbursements dymond_bank/workforce_payouts].each do |path|
  require ROOT.join("app/services", path).to_s
end
require ROOT.join("app/jobs/it_services/appointment_settlement_job").to_s
# Use the same integration registration as the host application.
require ROOT.join("config/initializers/it_services_billing").to_s
Rails.application.config.to_prepare_blocks.each(&:call)

class Current
  def self.session = nil
end
module LightekIdentity
  module Mfa
    def self.enabled?(_) = true
    def self.fresh?(_) = true
  end
end
require ROOT.join("app/controllers/it_service_billing_controller").to_s
require ROOT.join("app/controllers/dashboard/it_service_finance_controller").to_s
class Dashboard::ItServiceFinanceController
  # This harness uses header authentication. The native application supplies
  # the session and executes the existing SensitiveSession concern.
  skip_before_action :require_sensitive_session!
  layout false
end
ItServiceBillingController.layout false
ReservationHarness.routes.send(:eval_block, proc do
  eval(ROOT.join("config/routes/it_services_billing.rb").read, binding)
  get "/dashboard/people", to: "reservations#index", as: :dashboard_people
  get "/it_service_requests", to: "reservations#index", as: :it_service_requests
  get "/it_service_requests/new", to: "reservations#index", as: :new_it_service_request
end)

class ItServiceBusinessChecks < ActionDispatch::IntegrationTest
  def app = ReservationHarness
  def setup
    @fixtures = ReservationsChecks.new("unused")
    @fixtures.setup
    @owner, @guest, @other, @site, @start = %i[owner guest other site start].map { |key| @fixtures.instance_variable_get("@#{key}") }
    @staff = User.create!(email_address: "it-tech@example.test", role: "employee")
    @approver = User.create!(email_address: "pay-approver@example.test", role: "employee")
    @membership_resource = @fixtures.resource(kind: "service", name: "Managed IT appointment", capacity: 4)
    @product = @fixtures.product
    @product.update!(name: "Managed Business IT", product_type: "service", billing_interval: "month", track_inventory: false)
    @plan = ItServices::Plan.create!(product: @product, resource: @membership_resource)
    host! @site.host
  end

  def teardown
    [ItServiceEvent, Marlon::TicketEvent, Marlon::Ticket, ItServices::Payout, ItServices::CoverageClaim, ItServiceRequest,
      ItServices::CoveragePeriod, ItServices::Membership, ItServices::Plan, LightekCommerce::BillingInvoice,
      LightekCommerce::Subscription, LightekPeople::AuditEvent, LightekPeople::PayoutDestination, LightekPeople::PayStatement,
      LightekPeople::PayRun, LightekPeople::Employment].compact.each(&:delete_all)
  end

  def headers(user) = { "X-Test-User" => user.id.to_s }

  def paid_subscription
    membership = ItServices::Enrollment.reserve!(customer: @guest, plan: @plan)
    order = membership.order
    @first = 2.days.ago.change(usec: 0)
    @last = 28.days.from_now.change(usec: 0)
    reference = "sub_#{order.id}"
    remote = Stripe::Subscription.construct_from(id: reference, customer: "cus_fixture", status: "active",
      metadata: LightekCommerce::PaymentIdentity.metadata(order), items: { data: [{ price: { unit_amount: order.subtotal_cents,
        currency: "usd", recurring: { interval: "month", interval_count: 1 } }, quantity: 1,
        current_period_start: @first.to_i, current_period_end: @last.to_i }] })
    @initial_invoice = invoice_payload(reference, first: @first, last: @last, reason: "subscription_create")
    event = signed_event(@fixtures.event(order, mode: "subscription", subscription: reference, invoice: @initial_invoice.fetch(:id)))
    Stripe::Subscription.stub(:retrieve, remote) do
      Stripe::Invoice.stub(:retrieve, Stripe::Invoice.construct_from(@initial_invoice)) do
        2.times { LightekCommerce::StripeEvents.process!(event) }
      end
    end
    [membership.reload, remote]
  end

  def signed_event(event)
    payload = JSON.generate(event.to_hash)
    timestamp = Time.now
    secret = "whsec_it_services_fixture"
    digest = Stripe::Webhook::Signature.compute_signature(timestamp, payload, secret)
    header = Stripe::Webhook::Signature.generate_header(timestamp, digest)
    assert_raises(Stripe::SignatureVerificationError) { Stripe::Webhook.construct_event(payload, header, "wrong_secret") }
    Stripe::Webhook.construct_event(payload, header, secret)
  end

  def invoice_payload(reference, first:, last:, reason: "subscription_cycle", **overrides)
    { id: "in_#{SecureRandom.hex(6)}", billing_reason: reason, status: "paid", currency: "usd", subtotal: @product.price_cents,
      subscription: reference, total: @product.price_cents, amount_paid: @product.price_cents, status_transitions: { paid_at: 1.minute.ago.to_i },
      lines: { data: [{ amount: @product.price_cents, currency: "usd", period: { start: first.to_i, end: last.to_i },
        parent: { subscription_item_details: { subscription: reference, proration: false } } }] } }.merge(overrides)
  end

  def test_checkout_uses_signed_commerce_settlement_and_booking_requires_owner_and_paid_term
    assert_raises(LightekCommerce::OrderPlacement::Invalid) do
      LightekCommerce::OrderPlacement.call(site: @site, customer_email: @guest.email_address, quantities: { @product.id.to_s => 1 })
    end
    pending = ItServices::Enrollment.reserve!(customer: @guest, plan: @plan)
    assert_equal pending.id, ItServices::Enrollment.reserve!(customer: @guest, plan: @plan).id
    assert_raises(LightekReservations::Booking::Invalid) { @fixtures.reserve(resource: @membership_resource) }
    membership, = paid_subscription
    assert_equal pending.id, membership.id
    assert_equal "fulfilled", membership.order.status
    assert_equal 1, membership.coverage_periods.count
    assert_equal @last, membership.coverage_periods.sole.ends_at
    assert_raises(ItServices::Enrollment::Invalid) { ItServices::Enrollment.reserve!(customer: @guest, plan: @plan) }
    assert_raises(LightekReservations::Booking::Invalid) { @fixtures.reserve(resource: @membership_resource, customer: @other) }
    assert_raises(LightekReservations::Booking::Invalid) { @fixtures.reserve(resource: @membership_resource, start: @last - 1.minute) }
    assert_raises(LightekReservations::Booking::Invalid) { @fixtures.reserve(resource: @membership_resource, quantity: 2) }
    appointment = @fixtures.reserve(resource: @membership_resource)
    assert_equal "confirmed", appointment.status
    assert_nil appointment.order
    get "/my/it-services/billing", headers: headers(@guest)
    assert_response :success
    assert_includes response.body, @initial_invoice.fetch(:id)
    assert_includes response.body, "Book an included appointment"
    get "/my/it-services/billing", headers: headers(@other)
    assert_response :success
    refute_includes response.body, @initial_invoice.fetch(:id)
    get "/my/it-services/billing"
    assert_response :unauthorized
  end

  def test_verified_renewals_extend_coverage_and_failed_or_refunded_terms_do_not
    membership, remote = paid_subscription
    subscription = membership.subscription
    invoice = invoice_payload(subscription.processor_reference, first: 1.minute.ago, last: 2.months.from_now)
    remote.items.data.first.current_period_end = 2.months.from_now.to_i
    Stripe::Subscription.stub(:retrieve, remote) do
      event = Stripe::Event.construct_from(type: "invoice.paid", created: Time.current.to_i, data: { object: invoice })
      2.times { LightekCommerce::StripeEvents.process!(event) }
    end
    assert_equal 2, membership.coverage_periods.count
    appointment = @fixtures.reserve(resource: @membership_resource, start: 5.weeks.from_now)
    assert_equal "confirmed", appointment.status
    renewal = membership.coverage_periods.order(:id).last.invoice.settlement_order
    renewal.update!(status: "partially_refunded", refunded_cents: 1)
    assert_raises(LightekReservations::Booking::Invalid) do
      LightekReservations::Booking.reschedule!(reservation: appointment, actor: @guest, starts_at: 6.weeks.from_now.iso8601)
    end
    Stripe::Subscription.stub(:retrieve, Stripe::Subscription.construct_from(remote.to_hash.merge(status: "past_due"))) do
      LightekCommerce::StripeEvents.process!(Stripe::Event.construct_from(type: "invoice.payment_failed", created: Time.current.to_i, data: { object: invoice }))
    end
    assert_raises(LightekReservations::Booking::Invalid) { @fixtures.reserve(resource: @membership_resource) }
  end

  def test_cancellation_is_owner_scoped_and_preserves_paid_coverage
    membership, remote = paid_subscription
    assert_raises(ActiveRecord::RecordNotFound) do
      post "/my/it-services/billing/subscriptions/#{membership.id}/cancel", headers: headers(@other)
    end
    update = lambda do |ref, attributes, _options|
      assert_equal membership.subscription.processor_reference, ref
      assert_equal({ cancel_at_period_end: true }, attributes)
      Stripe::Subscription.construct_from(remote.to_hash.merge(cancel_at_period_end: true))
    end
    Stripe::Subscription.stub(:update, update) do
      post "/my/it-services/billing/subscriptions/#{membership.id}/cancel", headers: headers(@guest)
    end
    assert_response :see_other
    assert membership.subscription.reload.cancel_at_period_end?
    assert_equal "confirmed", @fixtures.reserve(resource: @membership_resource).status
  end

  def test_coverage_dispatch_and_customer_confirmed_payout_through_payroll
    membership, = paid_subscription
    reservation = @fixtures.reserve(resource: @membership_resource)
    request, ticket = build_case(reservation)
    if defined?(IT_BATCH_B_REAL)
      ItServices::ReservationAssignment.call!(request: request, reservation: reservation, actor: @guest)
      ItServices::TechnicianAssignment.call!(request: request, technician: @staff, actor: @owner, note: "Assigned to the IT support team.")
      ItServices::AppointmentDispatch.call!(request: request, actor: @owner, note: "Customer has paid managed coverage.")
      assert_equal "scheduled", request.reload.status
      ItServices::TechnicianResponse.call!(request: request, actor: @staff, decision: "accept", note: "Appointment accepted for customer.")
      ItServices::TechnicianWork.record!(request: request, actor: @staff, step: "verification", result: "passed",
        evidence: "Customer station passed the agreed connectivity test.")
      ItServices::Completion.submit!(request: request, actor: @staff, summary: "Customer station passed the agreed connectivity test.")
      assert_raises(ArgumentError) { ItServices::Completion.confirm!(request: request, actor: @other, confirmed: "confirmed", note: "Confirmed.") }
      ItServices::Completion.confirm!(request: request, actor: @guest, confirmed: "confirmed", note: "Confirmed.")
    else
      clearance = ItServices::PaymentClearance.verify!(request: request)
      resolve_fixture(request, ticket, clearance)
    end
    assert_equal "customer_confirmed", ticket.reload.extra_fields.dig("it_services_handoff", "state")
    assert_equal membership.coverage_periods.sole.id, ItServices::CoverageClaim.sole.period_id
    duplicate = ItServiceRequest.new(user: @guest, reservation: reservation, service_code: "managed_it",
      status: "triaged", delivery_mode: "onsite", service_location: "100 Main Street", description: "Second claimed request")
    assert_raises(ArgumentError) { ItServices::PaymentClearance.verify!(request: duplicate) }

    employment, run = payroll_for
    post "/dashboard/it-services/finance/payouts", params: { site_id: @site.id }, headers: headers(@other)
    assert_response :forbidden
    args = { site_id: @site.id, run_id: run.id, tax_reviewed: "1", request_ids: [request.id],
      gross_amounts: { request.id.to_s => 4000 }, deductions: { tax_cents: 400, employer_tax_cents: 100, other_deductions_cents: 0, tax_reference: "review-test" } }
    2.times do
      post "/dashboard/it-services/finance/payouts", params: args, headers: headers(@owner)
      assert_response :see_other
      assert_includes response.location, "/dashboard/people"
    end
    payout = ItServices::Payout.sole
    statement = payout.pay_statement
    assert_equal [employment.id, 4_000, 3_600], statement.attributes.values_at("employment_id", "gross_cents", "net_cents")
    assert_raises(ActiveRecord::RecordInvalid) { statement.update!(gross_cents: 4100, net_cents: 3700) }
    statement.reload
    assert_raises(LightekPeople::Payroll::Invalid) { LightekPeople::Payroll.new(access: access(@owner)).approve!(run: run) }

    sender = Struct.new(:financial_account_ref).new("fa_it_services")
    DymondBank::WorkforcePayouts.stub(:new, sender) do
      LightekPeople::Payroll.new(access: access(@approver)).approve!(run: run)
    end
    destination = LightekPeople::PayoutDestination.create!(employment: employment, recipient_ref: "acct_it_tech")
    statement.update!(provider_ref: "poi_it_services")
    provider = Object.new
    provider.define_singleton_method(:retrieve!) do |_reference|
      { "id" => "poi_it_services", "from" => { "financial_account" => "fa_it_services" },
        "to" => { "recipient" => destination.recipient_ref }, "amount" => { "value" => 3600, "currency" => "usd" }, "status" => "posted" }
    end
    LightekPeople::Disbursements.new(access: access(@approver), adapter: provider).perform!(statement: statement, action: "refresh")
    assert_equal "Posted", payout.reload.settlement_status
    get "/dashboard/it-services/finance", params: { site_id: @site.id }, headers: headers(@owner)
    assert_response :success
    assert_includes response.body, "Posted"
  end

  def test_one_time_appointment_reconciles_only_after_customer_confirmation
    resource = @fixtures.resource(kind: "service", product: @fixtures.product)
    resource.update!(it_service_appointment: true)
    reservation = @fixtures.reserve(resource: resource)
    LightekCommerce::StripeEvents.process!(@fixtures.event(reservation.order))
    reservation.reload
    assert_raises(LightekCommerce::Fulfillment::Invalid) do
      LightekCommerce::Fulfillment.complete!(order: reservation.order, reference: "manual")
    end
    LightekReservations::Settlement.complete_appointment!(reservation)
    request, ticket = build_case(reservation)
    assert_nil ItServices::CompletedAppointmentSettlement.call(request)
    assert_equal "paid", reservation.order.reload.status
    request.update!(reservation: reservation, technician: @staff)
    resolve_fixture(request, ticket, ItServices::PaymentClearance.verify!(request: request))
    2.times { ItServices::AppointmentSettlementJob.new.perform(request.id) }
    assert_equal "fulfilled", reservation.order.reload.status
    assert_equal "IT service request ##{request.id}", reservation.order.fulfillment_reference
  end

  private

  def build_case(reservation)
    request = ItServiceRequest.create!(user: @guest, service_code: "managed_it", status: "triaged", delivery_mode: "onsite",
      service_location: "100 Main Street", description: "Test a workstation’s access to the customer network.")
    unless defined?(IT_BATCH_B_REAL)
      request.update!(reservation: reservation, technician: @staff)
    end
    ticket = Marlon::Ticket.create!(related: request, title: "IT support", category: "technical", status: "open",
      extra_fields: { "source" => NevaehCustomerService::Cases::SOURCE })
    [request, ticket]
  end

  def resolve_fixture(request, ticket, clearance)
    request.update!(status: "resolved", closed_at: Time.current)
    ticket.update!(status: "resolved", extra_fields: ticket.extra_fields.merge("it_services_handoff" => {
      "state" => "customer_confirmed", "request_id" => request.id, "technician_id" => @staff.id, "completed_by_id" => @staff.id,
      "reservation_id" => request.reservation_id, "completion_summary" => "Customer station passed the connectivity test.",
      "payment_clearance" => clearance
    }))
  end

  def access(actor) = LightekPeople::Access.new(actor: actor, employer: @owner)

  def payroll_for
    worker = LightekPeople::Employment.create!(employer: @owner, worker: @staff, title: "Technician", starts_on: 1.month.ago.to_date)
    LightekPeople::Employment.create!(employer: @owner, worker: @approver, title: "Approver", payroll_access: "approver", starts_on: 1.month.ago.to_date)
    run = LightekPeople::PayRun.create!(employer: @owner, prepared_by: @owner, period_start: 1.day.ago.to_date,
      period_end: Date.current, pay_date: Date.current)
    [worker, run]
  end
end
