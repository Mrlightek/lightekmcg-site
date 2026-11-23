# frozen_string_literal: true

module LightekCommunications
  class Service < ApplicationRecord
    self.table_name = "lightek_communications_services"

    belongs_to :subscription, class_name: "LightekCommerce::Subscription"
    has_many :events, class_name: "LightekCommunications::ServiceEvent", dependent: :restrict_with_error

    validates :kind, inclusion: { in: %w[internet voice] }
    validates :status, inclusion: { in: %w[provisioning in_service suspended] }
  end
end
