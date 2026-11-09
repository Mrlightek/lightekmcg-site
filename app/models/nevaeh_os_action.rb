# frozen_string_literal: true
class NevaehOsAction < ApplicationRecord
  belongs_to :user
  validates :request_key, format: {with: /\A[a-zA-Z0-9_-]{8,100}\z/}, uniqueness: {scope: :user_id}
  validates :status, inclusion: {in: %w[pending completed failed]}
  validate do
    errors.add(:command, 'must be a bounded object') unless command.is_a?(Hash) && command.to_json.bytesize <= 32000
    errors.add(:command, 'is immutable') if persisted? && will_save_change_to_command?
    errors.add(:user_id, 'is immutable') if persisted? && will_save_change_to_user_id?
  end
end
