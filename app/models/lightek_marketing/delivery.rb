# frozen_string_literal: true
module LightekMarketing
  class Delivery < ApplicationRecord
    self.table_name = "lightek_marketing_deliveries"
    belongs_to :campaign, class_name: "LightekMarketing::Campaign"
    belongs_to :contact, class_name: "LightekMarketing::Contact"
    belongs_to :mail_message, class_name: "LightekMail::Message", optional: true
    validates :status, inclusion: {in: %w[pending queued failed]}
    validates :contact_id, uniqueness: {scope: :campaign_id}
  end
end
