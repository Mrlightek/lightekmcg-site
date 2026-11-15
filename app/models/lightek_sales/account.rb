# frozen_string_literal: true
module LightekSales
  class Account < ApplicationRecord
    self.table_name = 'lightek_sales_accounts'
    include SalesSiteRecord
    has_many :opportunities, class_name: 'LightekSales::Opportunity', dependent: :restrict_with_error
    has_many :contacts, class_name: 'LightekMarketing::Contact', foreign_key: :sales_account_id, dependent: :restrict_with_error
    before_validation do
      self.name = name.to_s.strip
      self.normalized_name = name.downcase
    end
    validates :name, presence: true, length: {maximum: 160}
    validates :normalized_name, uniqueness: {scope: :site_id}
    validates :website, length: {maximum: 300}
    validates :notes, length: {maximum: 20_000}
  end
end
