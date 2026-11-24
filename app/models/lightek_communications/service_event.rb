# frozen_string_literal: true

module LightekCommunications
  class ServiceEvent < ApplicationRecord
    self.table_name = "lightek_communications_service_events"

    belongs_to :service, class_name: "LightekCommunications::Service"
    belongs_to :operator, class_name: "User", optional: true
    belongs_to :billing_invoice, class_name: "LightekCommerce::BillingInvoice", optional: true

    validates :action, inclusion: { in: %w[register activate suspend restore] }
  end
end
