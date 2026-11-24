class ItServiceEvent < ApplicationRecord
  belongs_to :it_service_request
  belongs_to :actor, class_name: "User"
  validates :from_status, :to_status, inclusion: { in: ItServiceRequest::STATUSES }
  validates :note, presence: true, length: { maximum: 2000 }
end
