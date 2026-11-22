# frozen_string_literal: true

module NevaehCustomerService
  module Refunds
    module_function

    def approve!(ticket:, actor:, amount_cents:)
      amount = Integer(amount_cents.to_s, 10, exception: false)
      ticket.with_lock do
        state = ticket.extra_fields.to_h["customer_service"]
        unless Cases.customer_case?(ticket) && state["topic"] == "refund_request" && ticket.status != "resolved"
          raise Cases::Invalid, "Choose an open refund case"
        end
        order = authorized_order!(ticket, actor)
        unless amount&.positive? && amount <= order.total_cents - order.refunded_cents
          raise Cases::Invalid, "Enter an amount in cents within the remaining refundable balance"
        end
        raise Cases::Invalid, "A refund decision was already recorded" if state.key?("refund")

        save!(ticket, state, {"phase" => "approved", "actor_id" => actor.id, "amount_cents" => amount})
        ticket.log!(action: "Refund approved", actor: actor)
      end
    end

    def execute!(ticket)
      order = nil
      state = nil
      approval = nil
      ticket.with_lock do
        state = ticket.extra_fields.to_h["customer_service"]
        approval = state&.fetch("refund", nil)
        return unless Cases.customer_case?(ticket) && approval && approval["phase"] == "approved"
        if ticket.status == "resolved"
          save!(ticket, state, approval.merge("phase" => "blocked"))
          return
        end

        actor = User.find_by(id: approval.fetch("actor_id"))
        begin
          order = authorized_order!(ticket, actor)
        rescue Cases::Invalid, ActiveRecord::RecordNotFound
          save!(ticket, state, approval.merge("phase" => "blocked"))
          return
        end
        save!(ticket, state, approval.merge("phase" => "submitting"))
      end

      # Keep the claim committed before contacting the payment processor.
      # An interrupted attempt is reconciled by key. It is never replayed.
      LightekCommerce::Refunds.issue!(order: order, amount_cents: approval.fetch("amount_cents"), idempotency_key: key(ticket))
    rescue LightekCommerce::Refunds::Invalid, Stripe::StripeError
      ticket.with_lock do
        state = ticket.extra_fields.fetch("customer_service")
        save!(ticket, state, state.fetch("refund").merge("phase" => "review_required"))
      end
    ensure
      reconcile!(ticket) if order
    end

    def reconcile!(ticket)
      ticket.with_lock do
        state = ticket.extra_fields.to_h["customer_service"]
        approval = state&.fetch("refund", nil)
        return unless approval && %w[submitting pending review_required].include?(approval["phase"])
        return unless ticket.related_type == "LightekCommerce::Order"

        refund = LightekCommerce::Refund.find_by(order_id: ticket.related_id, idempotency_key: key(ticket))
        return unless refund && refund.amount_cents == approval.fetch("amount_cents")
        return if approval["phase"] == refund.status

        save!(ticket, state, approval.merge("phase" => refund.status, "refund_id" => refund.id))
        if refund.status == "succeeded"
          ticket.update!(status: "resolved", resolved_at: Time.current)
          ticket.log!(action: Cases::CUSTOMER_UPDATE, detail: "Your installation refund was confirmed.")
        elsif refund.status == "failed"
          ticket.log!(action: Cases::CUSTOMER_UPDATE, detail: "The refund could not be completed. Accounting & Billing is reviewing it.")
        end
      end
    end

    def authorized_order!(ticket, actor)
      customer = ticket.submitted_by
      unless LightekPeople::LifecycleAccess.active?(customer) && LightekPeople::LifecycleAccess.active?(actor) &&
        actor.admin? && LightekIdentity::Mfa.enabled?(actor) && ticket.related_type == "LightekCommerce::Order"
        raise Cases::Invalid, "An active accounting operator with an authenticator is required"
      end

      order = Cases.refundable_installations(customer).find(ticket.related_id)
      LightekSettings::WebsiteIdentity.sites_for(actor).find(order.site_id)
      order
    end

    def key(ticket) = "customer-service-refund-#{ticket.id}"

    def save!(ticket, state, approval)
      ticket.update!(extra_fields: ticket.extra_fields.merge("customer_service" => state.merge("refund" => approval)))
    end
  end
end
