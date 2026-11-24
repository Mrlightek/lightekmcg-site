module ItServices
  class NevaehTriage
    # A support recommendation, not authorization to execute endpoint commands.
    def self.call!(request:, actor:)
      raise ArgumentError, "Customer ownership required" unless actor&.persisted? && request.user_id == actor.id
      result = { request_id: request.id, service: request.service_code,
        delivery_mode: request.delivery_mode, outcome: "specialist_required",
        reason: "A technician must review the customer's reported symptoms.",
        next_action: "Review intake and arrange a diagnostic appointment." }
      if request.delivery_mode == "onsite"
        result[:reason] = "On-site assistance requested."
        result[:next_action] = "Arrange an on-site appointment and technician dispatch."
        return result
      end
      if request.network_managed_device.nil?
        result[:reason] = "No verified customer-owned device is linked."
        result[:next_action] = "Verify ownership and link an enrolled device, or arrange a technician."
        return result
      end
      consent = ItServiceDiagnosticConsent.find_by(it_service_request: request)
      unless consent&.active? && consent.granted_by_id == actor.id
        result[:reason] = "Read-only diagnostic consent has not been granted."
        result[:next_action] = "Request customer consent or schedule a technician."
        return result
      end
      report = DiagnosticInterpreter.call!(request: request, actor: actor)
      result[:diagnostic_source] = report[:source]
      result[:findings] = report[:findings].map { |finding| finding.slice(:code, :severity, :summary, :recommendation) }
      result[:reason] = report[:limitations]
      result[:next_action] = report[:recommended_next_step]
      result
    end
  end
end
