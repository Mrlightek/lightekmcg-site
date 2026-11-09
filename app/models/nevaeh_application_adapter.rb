# frozen_string_literal: true
class NevaehApplicationAdapter < ApplicationRecord
  belongs_to :user
  validates :package, format: {with: /\A[a-z0-9][a-z0-9+.-]{1,100}\z/}, uniqueness: {scope: :user_id}
  validates :name, presence: true, length: {maximum:160}
  validates :status, inclusion: {in: %w[draft active]}
  validate do
    errors.add(:operations,'must be a bounded object') unless operations.is_a?(Hash) && operations.size <= 30 && operations.to_json.bytesize <= 32000
  end
  before_update do
    if will_save_change_to_operations? || will_save_change_to_package?
      self.status='draft'; self.verification={}
    end
  end
end
