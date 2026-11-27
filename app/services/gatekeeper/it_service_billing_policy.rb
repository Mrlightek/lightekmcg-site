module Gatekeeper
  class ItServiceBillingPolicy
    class Denied < ArgumentError; end

    def self.coverage!(customer:, resource:, starts_at:, ends_at:)
      plan = ItServices::Plan.find_by(resource: resource)
      return unless plan
      raise Denied, "Managed IT appointment coverage is unavailable" unless customer&.access_active? && plan.compatible?

      now = Time.current
      # Access is current at booking/dispatch and the entire visit fits in the paid term.
      period = ItServices::CoveragePeriod.joins(:invoice, membership: :order).includes(:invoice, membership: { order: :commerce_subscription })
        .where(it_service_memberships: { plan_id: plan.id, customer_id: customer.id })
        .where("it_service_coverage_periods.starts_at <= ? AND it_service_coverage_periods.ends_at > ? AND it_service_coverage_periods.ends_at >= ?", now, now, ends_at)
        .order(ends_at: :desc).find do |candidate|
          subscription = candidate.membership.subscription
          subscription&.status == "active" && subscription.current_period_end && subscription.current_period_end >= ends_at &&
            candidate.invoice.paid_at <= now && starts_at >= candidate.starts_at &&
            funded_order?(candidate.membership.order) && funded_order?(candidate.invoice.settlement_order)
        end
      period || raise(Denied, "An active, paid Managed IT subscription must cover the appointment.")
    end

    def self.funded_order?(order)
      order && order.paid_at? && order.status.in?(%w[paid fulfilled]) && order.refunded_cents.zero? &&
        !order.refunds.where(status: "pending").exists?
    end
  end
end
