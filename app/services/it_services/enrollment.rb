module ItServices
  class Enrollment
    class Invalid < StandardError; end

    def self.operations_ready?
      defined?(ItServices::PaymentClearance) && defined?(ItServiceRequest) && ItServiceRequest.table_exists?
    end

    def self.reserve!(customer:, plan:)
      raise Invalid, "Sign in with your own active account" unless customer&.persisted? && customer.access_active?

      customer.with_lock do
        existing = Membership.open.where(customer: customer, plan: plan).includes(order: :commerce_subscription).order(id: :desc)
        pending = existing.find { |membership| membership.order.status == "pending_payment" }
        return pending if pending

        if existing.any? { |membership| membership.subscription && !membership.subscription.status.in?(%w[canceled incomplete_expired]) }
          raise Invalid, "You already have this subscription. Manage it in IT Services billing."
        end
        raise Invalid, "This service plan is unavailable" unless plan.reload.available?

        order = LightekCommerce::OrderPlacement.call(site: plan.product.site, customer_email: customer.email_address,
          quantities: { plan.product_id.to_s => 1 }, buyer: customer, it_service_plan: plan)
        Membership.create!(customer: customer, plan: plan, order: order)
      end
    end

    def self.cancel!(membership:, customer:)
      raise Invalid, "Subscription is unavailable" unless customer&.access_active? && membership.customer_id == customer.id
      return if membership.subscription&.cancel_at_period_end?
      raise Invalid, "There is no cancellable subscription" unless membership.cancellable?

      LightekCommerce::SubscriptionCancellation.schedule!(subscription: membership.subscription)
    end
  end
end
