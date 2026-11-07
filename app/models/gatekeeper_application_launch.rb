class GatekeeperApplicationLaunch < ApplicationRecord
  belongs_to :gatekeeper_application_template
  belongs_to :gatekeeper_node, optional: true
  belongs_to :provisioning_request, optional: true
  belongs_to :owner, class_name: "User"
  belongs_to :requested_by, class_name: "User"
  validates :name, presence: true, length: {maximum: 120}
  validates :domain, presence: true, uniqueness: true
  validates :status, inclusion: {in: %w[queued provisioning ready failed deleted]}
end
