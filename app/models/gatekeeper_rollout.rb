class GatekeeperRollout < ApplicationRecord
  belongs_to :gatekeeper_release
  has_many :gatekeeper_update_targets, dependent: :restrict_with_error
  validates :requested_by, presence: true
  validates :status, inclusion: {in: %w[draft running paused canary_ready completed canceled]}
  validates :canary_size, :batch_size, numericality: {only_integer: true, greater_than: 0, less_than_or_equal_to: 50}
  attr_readonly :gatekeeper_release_id, :requested_by, :canary_size, :batch_size, :auto_promote, :scheduled_at
end
