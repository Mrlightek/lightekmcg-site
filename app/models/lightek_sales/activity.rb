# frozen_string_literal: true
module LightekSales
  class Activity < ApplicationRecord
    self.table_name = 'lightek_sales_activities'
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :actor, class_name: 'User'
    belongs_to :record, polymorphic: true
    validates :record_type, inclusion: {in: %w[LightekSales::Lead LightekSales::Account LightekSales::Opportunity LightekMarketing::Contact LightekSales::RoutingRule]}
    validates :kind, inclusion: {in: %w[created updated converted note call meeting email inquiry_received task_created task_completed task_snoozed task_canceled]}
    validates :body, presence: true, length: {maximum: 20_000}
    validate { errors.add(:record, 'must belong to this website') if record && record.site_id != site_id }
  end
end
