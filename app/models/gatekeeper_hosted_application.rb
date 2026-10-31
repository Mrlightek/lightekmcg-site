class GatekeeperHostedApplication < ApplicationRecord
  belongs_to :gatekeeper_node
  belongs_to :gatekeeper_project
  belongs_to :owner, class_name: "User"
  belongs_to :requested_by, class_name: "User"
  belongs_to :gatekeeper_operation, optional: true
  before_validation { self.public_key ||= SecureRandom.uuid }
  validates :name, presence: true, length: {maximum: 120}
  validates :domain, presence: true, uniqueness: true, length: {maximum: 253},
    format: {with: /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+\z/}
  validates :public_key, uniqueness: true, format: {with: /\A[0-9a-f-]{36}\z/}
  validates :status, inclusion: {in: %w[queued provisioning ready failed deleted]}
end
