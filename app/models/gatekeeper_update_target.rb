class GatekeeperUpdateTarget < ApplicationRecord
  belongs_to :gatekeeper_rollout
  belongs_to :gatekeeper_installation
  belongs_to :gatekeeper_operation, optional: true
  validates :status, inclusion: {in: %w[pending reserved queued running succeeded failed canceled]}
end
