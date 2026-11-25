# frozen_string_literal: true

module ItServices
  # A preflight gate, not a remote executor. A customer must explicitly opt in
  # for this case and owned device; revocation blocks subsequent preflights.
  class RemoteDiagnosticAuthorization
    def self.verify!(request:, technician:)
      raise ArgumentError, "Active assigned technician required" unless technician&.persisted? &&
        technician.access_active? && request.technician_id == technician.id
      raise ArgumentError, "Accepted remote appointment required" unless request.status == "in_progress" &&
        request.delivery_mode == "remote"
      device = request.network_managed_device
      raise ArgumentError, "Verified customer device required" unless device &&
        device.owner_id == request.user_id && device.status == "active" &&
        device.enrolled_at.present? && device.last_seen_at.present? && !device.heartbeat_stale?
      consent = ItServiceDiagnosticConsent.find_by(it_service_request: request)
      raise ArgumentError, "Customer diagnostic consent required" unless consent&.active? &&
        consent.granted_by_id == request.user_id && consent.granted_at.present?
      {
        "request_id" => request.id, "device_id" => device.id,
        "technician_id" => technician.id, "consent_id" => consent.id,
        "consent_granted_at" => consent.granted_at.iso8601(6),
        "scope" => "read_only_diagnostic_preflight",
        "remote_execution_authorized" => false,
        "checked_at" => Time.current.iso8601(6)
      }
    end
  end
end
