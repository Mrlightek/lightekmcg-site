# frozen_string_literal: true
module LightekSales
  class IntakeEntry < ApplicationRecord
    self.table_name = 'lightek_sales_intake_entries'
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :inquiry, class_name: 'WebsiteTemplateInquiry', optional: true
    belongs_to :lead, class_name: 'LightekSales::Lead', optional: true
    belongs_to :created_by, class_name: 'User'
    belongs_to :processed_by, class_name: 'User', optional: true
    validates :origin, inclusion: {in: %w[website csv]}
    validates :origin_key, presence: true, uniqueness: {scope: :site_id}, length: {maximum: 160}
    validates :source, presence: true, length: {maximum: 80}
    validates :status, inclusion: {in: %w[awaiting_review needs_review imported duplicate ignored]}
    validates :error_message, length: {maximum: 300}
    validate do
      errors.add(:payload, 'must contain supported text fields') unless payload.is_a?(Hash) && (payload.keys - IntakeRule::TARGETS).empty? && payload.values.all? { |v| v.is_a?(String) && v.length <= 2000 }
      errors.add(:original, 'must be a small object') unless original.is_a?(Hash) && original.to_json.bytesize <= 16_000
      [:inquiry, :lead].each do |key|
        relation = public_send(key)
        errors.add(key, 'must belong to this website') if relation && relation.site_id != site_id
      end
    end
    def processed? = status.in?(%w[imported duplicate ignored])
  end
end
