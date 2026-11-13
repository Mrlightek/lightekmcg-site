module LightekAccounting
  class Category < ApplicationRecord
    self.table_name = 'lightek_accounting_categories'
    belongs_to :book
    validates :name, presence: true, length: {maximum: 120}
    validates :kind, inclusion: {in: %w[income expense transfer equity]}
    validates :deduction_bps, numericality: {only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 10000}
  end
end
