module LightekConnect
  class Sandbox < ApplicationRecord
    self.table_name = "lightek_connect_sandboxes"
    belongs_to :user
    belongs_to :gatekeeper_node
    validates :key, format: {with: /\A[0-9a-f]{24}\z/}
    validates :domain, uniqueness: true, presence: true
    validates :status, inclusion: {in: %w[queued installing ready failed deleting destroying delete_failed deleted]}
  end
end
