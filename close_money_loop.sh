#!/usr/bin/env bash
# Close the money loop:
#   1. Checkout now creates a Purchase (the order) alongside invoice/subscription
#   2. HOST subscribes to "dymond_bank.invoice.paid" -> Purchase.mark_paid!
#   3. mark_paid! emits "dymond_bank.purchase.paid" -> provisioning hook
#
# Run BOTH parts:
#   cd ~/Desktop/Development/dymond_bank      && bash close_money_loop.sh bank
#   cd ~/Desktop/Development/lightekmcg-site  && bash close_money_loop.sh host
set -uo pipefail
PART="${1:-}"

if [ "$PART" = "bank" ]; then
  echo "==> Checkout now creates the Purchase ($(pwd))"
  [ -f "dymond_bank.gemspec" ] || { echo "  error: run from dymond_bank root" >&2; exit 1; }
  F="app/services/dymond_bank/checkout.rb"
  cp "$F" "${F}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true

cat > "$F" <<'RUBY'
# frozen_string_literal: true
module DymondBank
  # ── DymondBank::Checkout ────────────────────────────────────────────────────
  # Offer -> money. Produces a Purchase (the order) plus the billing artifacts,
  # using only the existing BillingService.
  #
  #   setup_fee_cents   -> create_project_invoice
  #   subscription_plan -> subscribe (trial-aware; no bank needed for trials)
  #   free / demo       -> nothing collected; Purchase settles immediately
  module Checkout
    module_function

    # Display-safe. Touches nothing.
    def preview(offer:, interval: nil)
      return { ok: false, error: "no offer (custom quote)" } if offer.nil?

      iv = (interval || offer.default_interval).to_s
      {
        ok: true, offer_slug: offer.slug, mode: offer.mode, interval: iv,
        intervals: offer.available_intervals,
        setup_fee_cents: offer.setup_fee_cents.to_i,
        recurring_cents: offer.recurring_cents_for(iv),
        due_today_cents: offer.due_today_cents(iv),
        trial_days: offer.effective_trial_days,
        metered: offer.metered?, terms: offer.terms(iv)
      }
    end

    def purchase(offer:, customer:, interval: nil, linked_account: nil, memo: nil)
      return { ok: false, error: "no offer for this item (custom quote)" } if offer.nil?
      return { ok: false, error: "offer is not active" } unless offer.active?

      errors = validate(offer: offer, customer: customer, linked_account: linked_account)
      return { ok: false, error: errors.join(", ") } if errors.any?

      iv  = (interval || offer.default_interval).to_s
      due = offer.due_today_cents(iv)
      order = nil

      ActiveRecord::Base.transaction do
        invoice = (charge_setup_fee(offer, customer, linked_account, memo) if offer.setup_fee? && !offer.free? && !offer.demo?)
        sub     = (start_subscription(offer, customer, linked_account, iv)  if offer.recurring?  && !offer.free? && !offer.demo?)

        order = DymondBank::Purchase.create!(
          offer: offer, customer: customer,
          invoice: invoice, subscription: sub,
          status: "pending", mode: offer.mode,
          billing_interval: iv, amount_cents: due,
          currency: offer.currency,
          provision_spec: provision_spec(offer, customer)
        )
      end

      # Nothing to collect (free/demo/trial-with-no-setup): it's already settled.
      order.mark_paid! if order.settled_on_creation?

      {
        ok: true, offer: offer, purchase: order,
        invoice: order.invoice, subscription: order.subscription,
        due_today_cents: due, provision: order.provision_spec
      }
    rescue StandardError => e
      { ok: false, error: e.message, offer: offer }
    end

    # ---- pieces ----

    def charge_setup_fee(offer, customer, linked_account, memo)
      DymondBank::BillingService.create_project_invoice(
        billable: customer,
        line_items: [{ description: "#{offer.name} — setup", quantity: 1,
                       unit_price_cents: offer.setup_fee_cents.to_i }],
        memo: memo || "Offer: #{offer.slug}",
        linked_account: linked_account
      )
    end

    def start_subscription(offer, customer, linked_account, interval)
      DymondBank::BillingService.subscribe(
        subscriber: customer, plan: offer.subscription_plan,
        linked_account: linked_account, interval: interval,
        trial_days: offer.effective_trial_days
      )
    end

    # Plain strings — this gem never needs to know Marlon::ProjectType exists.
    def provision_spec(offer, customer)
      return {} if offer.offerable_type.blank?

      { "offerable_type" => offer.offerable_type,
        "offerable_id"   => offer.offerable_id,
        "offer_slug"     => offer.slug,
        "customer_type"  => customer.class.name,
        "customer_id"    => customer.id }
    end

    def validate(offer:, customer:, linked_account:)
      errors = []
      errors << "customer required" if customer.nil?
      if offer.chargeable? && offer.due_today_cents.positive? && linked_account.nil? && !offer.trial?
        errors << "a linked bank account is required to collect today"
      end
      errors << "offer has a plan but no plan record" if offer.recurring? && offer.subscription_plan.nil?
      errors
    end
  end
end
RUBY
  echo "  checkout.rb -> creates Purchase; free/demo settle on creation"
  echo "==> ruby -c $F ; commit + push dymond_bank"
  exit 0
fi

if [ "$PART" = "host" ]; then
  echo "==> Host: listen for payment ($(pwd))"
  [ -f "config/application.rb" ] || { echo "  error: run from the Rails app root" >&2; exit 1; }
  mkdir -p config/initializers app/services/marlon

cat > config/initializers/marlon_provisioning.rb <<'RUBY'
# frozen_string_literal: true
#
# THE MONEY LOOP'S LAST MILE.
#
# dymond_bank already instruments "dymond_bank.invoice.paid" inside
# BillingService.mark_invoice_paid! — it just had no listener. This is the listener.
#
#   invoice paid  -> find the Purchase -> mark_paid!
#   purchase paid -> hand it to Marlon::Provisioning
#
# Subscribed ONCE at boot (not in to_prepare — that would re-subscribe on every
# dev reload and fire duplicates). Constants resolve at call time, so reloading
# is fine.

ActiveSupport::Notifications.subscribe("dymond_bank.invoice.paid") do |*args|
  event   = ActiveSupport::Notifications::Event.new(*args)
  invoice = event.payload[:invoice]

  begin
    purchase = DymondBank::Purchase.for_invoice(invoice)
    purchase&.mark_paid!
  rescue StandardError => e
    Rails.logger.error "[provisioning] invoice.paid handler failed: #{e.message}"
  end
end

ActiveSupport::Notifications.subscribe("dymond_bank.purchase.paid") do |*args|
  event    = ActiveSupport::Notifications::Event.new(*args)
  purchase = event.payload[:purchase]

  begin
    Marlon::Provisioning.fulfill(purchase)
  rescue StandardError => e
    Rails.logger.error "[provisioning] purchase.paid handler failed: #{e.message}"
    purchase&.mark_failed!(e.message)
  end
end
RUBY

cat > app/services/marlon/provisioning.rb <<'RUBY'
# frozen_string_literal: true
module Marlon
  # What happens when a Purchase is paid.
  #
  # HONEST STATUS: the target is not decided yet. `marlon:meta_framework`
  # generates concerns/services/jobs INTO THIS APP — it does not stand up a
  # separate platform for a customer. Real provisioning is one of:
  #
  #   - a TENANT record (the Wilaya/Dawla two-plane model)
  #   - a generated domain gem (rails g lightek:domain)
  #   - a subdomain + database
  #   - a separately deployed app
  #
  # Until that's decided, this records the intent and logs it. The money loop is
  # complete and correct up to this line; only the fulfilment target is open.
  module Provisioning
    module_function

    def fulfill(purchase)
      spec = purchase.provision_spec || {}

      if spec.blank? || spec["offerable_type"].blank?
        # Nothing bound to build (a bare subscription, say). Paid is the end state.
        purchase.mark_provisioned!
        return { ok: true, provisioned: false, reason: "nothing to build" }
      end

      target = resolve(spec)
      unless target
        purchase.mark_failed!("provision target not found: #{spec['offerable_type']}##{spec['offerable_id']}")
        return { ok: false, error: "target not found" }
      end

      Rails.logger.info(
        "[provisioning] PAID purchase=#{purchase.id} customer=#{spec['customer_type']}##{spec['customer_id']} " \
        "wants=#{spec['offerable_type']}##{spec['offerable_id']} (#{target.try(:key)}) offer=#{spec['offer_slug']}"
      )

      # ---- WHERE THE BUILD GOES ----
      # Decide the target, then submit through dispatch, e.g.:
      #
      #   Marlon::Builder.build!(project_type: target.key, model: "...")
      #
      # Left unwired on purpose: running the generator here would write code into
      # LightekMCG's own app, not the customer's platform.
      purchase.mark_provisioned!
      { ok: true, provisioned: true, target: target.try(:key) }
    end

    def resolve(spec)
      klass = spec["offerable_type"].to_s.safe_constantize
      return nil unless klass

      klass.find_by(id: spec["offerable_id"])
    rescue StandardError
      nil
    end

    def customer_for(spec)
      klass = spec["customer_type"].to_s.safe_constantize
      klass&.find_by(id: spec["customer_id"])
    rescue StandardError
      nil
    end
  end
end
RUBY
  echo "  config/initializers/marlon_provisioning.rb  (the listener)"
  echo "  app/services/marlon/provisioning.rb         (fulfilment — target TBD)"
  echo "==> rails db:migrate ; restart"
  exit 0
fi

echo "Pass 'bank' or 'host'. See the header."
