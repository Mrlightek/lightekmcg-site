module ItServices
  class Payout < ApplicationRecord
    self.table_name = "it_service_payouts"

    belongs_to :employer, class_name: "User"
    belongs_to :technician, class_name: "User"
    belongs_to :prepared_by, class_name: "User"
    belongs_to :pay_statement, class_name: "LightekPeople::PayStatement"

    attr_readonly :service_request_id, :employer_id, :technician_id, :prepared_by_id, :gross_cents
    validates :gross_cents, numericality: { only_integer: true, in: 1..100_000_000 }

    def settlement_status
      statement = pay_statement
      return "Canceled" if statement.pay_run.status == "canceled"
      return "Needs reconciliation" if statement.error_code.present?
      return statement.provider_ref.present? ? "Posted" : "Needs reconciliation" if statement.status == "posted"

      statement.status.humanize
    end
  end
end
