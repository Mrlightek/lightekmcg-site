module ItServices
  class CoveragePeriod < ApplicationRecord
    self.table_name = "it_service_coverage_periods"

    belongs_to :membership
    belongs_to :invoice, class_name: "LightekCommerce::BillingInvoice"

    attr_readonly :membership_id, :invoice_id, :starts_at, :ends_at
  end
end
