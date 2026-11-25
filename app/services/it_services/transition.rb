module ItServices
  class Transition
    ALLOWED = {
      "requested" => %w[triaged cancelled],
      "triaged" => %w[awaiting_customer cancelled],
      "scheduled" => %w[cancelled],
      "in_progress" => %w[cancelled],
      "awaiting_customer" => %w[cancelled],
      "resolved" => [],
      "cancelled" => []
    }.freeze

    def self.call!(request:, actor:, to:, note:)
      raise ArgumentError, "Staff authorization required" unless actor&.role == "super_admin"
      raise ArgumentError, "Explain the status change" if note.to_s.strip.empty? || note.to_s.length > 2000
      request.with_lock do
        from = request.status
        raise ArgumentError, "Invalid status transition" unless ALLOWED.fetch(from, []).include?(to)
        request.update!(status: to, closed_at: %w[resolved cancelled].include?(to) ? Time.current : nil)
        ItServiceEvent.create!(it_service_request: request, actor: actor, from_status: from, to_status: to, note: note.strip)
      end
      request
    end
  end
end
