# Run using bin/rails runner on the deployed release. Prints readiness only.
checks = {}
checks["Batch B case and payment-clearance contracts"] = ItServices::Enrollment.operations_ready? &&
  ItServices::PaymentClearance.singleton_class.ancestors.include?(ItServices::CoveredPaymentClearance) &&
  ItServiceRequest.ancestors.include?(ItServices::SettlesCompletedAppointments)

checks["Batch C database tables"] = [
  ItServices::Plan, ItServices::Membership, ItServices::CoveragePeriod, ItServices::CoverageClaim, ItServices::Payout
].all?(&:table_exists?)

routes = Rails.application.routes.url_helpers
checks["Customer billing and Dashboard finance routes"] = routes.respond_to?(:it_service_billing_path) &&
  routes.respond_to?(:dashboard_it_service_finance_path)
checks["Shared Dymond Bank webhook routing"] = DymondBank::StripeWebhookService.singleton_class
  .ancestors.include?(LightekCommerceStripeRouting)

if Rails.env.production? || ENV["IT_SERVICES_VERIFY_WORKER"] == "1"
  require "sidekiq/api"
  checks["Sidekiq appointment settlement queue"] = Sidekiq::ProcessSet.new(false).any? do |process|
    Array(process["queues"]).include?(ItServices::AppointmentSettlementJob.new.queue_name)
  end
end

checks.each { |check, ready| puts "#{ready ? 'PASS' : 'FAIL'} #{check}" }
abort "IT Services release checks failed." unless checks.values.all?
