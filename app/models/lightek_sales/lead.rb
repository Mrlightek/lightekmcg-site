# frozen_string_literal: true
module LightekSales
  class Lead < ApplicationRecord
    self.table_name = 'lightek_sales_leads'
    include SalesSiteRecord
    STATUSES = %w[new contacted qualified disqualified converted].freeze
    belongs_to :opportunity, class_name: 'LightekSales::Opportunity', optional: true
    before_validation do
      self.email = email.to_s.strip.downcase
      self.source = source.to_s.strip.downcase.presence || 'manual'
    end
    before_validation do
      self.name = name.to_s.strip
      self.company = company.to_s.strip
      self.next_step = next_step.to_s.strip.presence
    end
    validates :name, :company, presence: true, length: {maximum: 160}
    validates :email, presence: true, uniqueness: {scope: :site_id}, format: {with: URI::MailTo::EMAIL_REGEXP}, length: {maximum: 254}
    validates :source, length: {maximum: 80}
    validates :status, inclusion: {in: STATUSES}
    validates :phone, length: {maximum: 80}
    validates :next_step, length: {maximum: 300}
    validates :notes, length: {maximum: 20_000}
    validate { same_sales_site(:opportunity) }
    validate do
      errors.add(:status, 'must be changed through Convert lead') if status == 'converted' && opportunity_id.blank?
      errors.add(:status, 'cannot reopen a converted lead; work its deal instead') if converted_at_was.present? && changed?
    end
    scope :active, -> { where(status: %w[new contacted qualified]) }
  end
end
