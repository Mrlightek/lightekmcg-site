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
