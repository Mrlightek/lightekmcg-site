module ItServices
  class TechnicianAssignment
    ELIGIBLE_ROLES = %w[employee contractor admin].freeze

    def self.call!(request:, technician:, actor:, note:)
      raise ArgumentError, "Super admin authorization required" unless actor&.role == "super_admin"
      raise ArgumentError, "Technician must be an active employee or contractor" unless technician&.persisted? &&
        ELIGIBLE_ROLES.include?(technician.role) && technician.access_active?
      raise ArgumentError, "Explain the assignment" unless note.to_s.strip.length.between?(1, 2000)
      request.with_lock do
        raise ArgumentError, "Only requested or triaged work can be assigned" unless request.status.in?(%w[requested triaged])
        previous = request.technician_id
        request.update!(technician: technician, technician_assigned_at: Time.current)
        ItServiceEvent.create!(it_service_request: request, actor: actor, from_status: request.status,
          to_status: request.status, note: "Technician assigned: user ##{technician.id} (previous: #{previous || 'none'}). #{note.strip}")
      end
      request
    end
  end
end
