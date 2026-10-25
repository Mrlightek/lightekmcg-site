# frozen_string_literal: true
module LightekMarketplace
  module InvoiceSettlement
    def succeed_transaction!(txn)
      invoice = txn.invoice
      purchase = invoice && DymondBank::Purchase.find_by(invoice_id: invoice.id)
      managed = purchase && [88, 89].include?(purchase.offer.meta.to_h.dig("lightek_marketplace", "version"))
      return super unless managed
      invoice.with_lock do
        txn.reload
        return super if txn.succeeded?
        unless txn.transaction_type == "charge" && txn.amount_cents.to_i == invoice.amount_remaining_cents.to_i &&
            txn.currency.to_s.upcase == invoice.currency.to_s.upcase && invoice.open?
          raise ArgumentError, "Settlement does not match the open order invoice"
        end
        super
      end
    end
  end
end
