# frozen_string_literal: true
module LightekPwa
  class Money
    def self.call(user)
      raise LightekCommunity::AccessDenied, "Sign in to view your financial activity" unless user
      accounts = user.bank_accounts
      invoices = user.invoices
      transactions = DymondBank::Transaction.where(account_id: accounts.select(:id))
        .or(DymondBank::Transaction.where(invoice_id: invoices.select(:id)))
      studio = StudioProject.where(owner_id: user.id).select(:id)
      transactions = transactions.or(DymondBank::Transaction.where(payable_type: "StudioOperation",
        payable_id: StudioOperation.where(studio_project_id: studio).select(:id)))
      {
        accounts: accounts.order(:id).map { |a| a.attributes.slice("id", "display_name", "currency", "balance_cents", "available_cents", "status") },
        invoices: invoices.order(id: :desc).limit(50).map { |i| i.attributes.slice("id", "number", "status", "currency", "total_cents", "amount_paid_cents", "amount_remaining_cents", "due_date") },
        transactions: transactions.order(id: :desc).limit(50).map { |t| t.attributes.slice("id", "status", "transaction_type", "currency", "amount_cents", "fee_cents", "created_at") }
      }
    end
  end
end
