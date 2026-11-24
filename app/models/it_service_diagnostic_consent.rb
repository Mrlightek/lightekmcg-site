class ItServiceDiagnosticConsent < ApplicationRecord
  belongs_to :it_service_request
  belongs_to :granted_by, class_name: "User"
  validates :granted_at, presence: true
  def active? = revoked_at.nil?
end
