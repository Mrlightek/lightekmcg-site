# frozen_string_literal: true

module ItServices
  class RemoteSupportCaseReceipt
    def self.record!(room, actor_id)
      work = room.it_service_request
      return unless room.ended_at? && work&.user_id == room.customer_id
      ticket = Marlon::Ticket.where(related: work, submitted_by_id: room.customer_id)
        .where("extra_fields->>'source' = ?", NevaehCustomerService::Cases::SOURCE).order(id: :desc).first
      return unless ticket

      ticket.with_lock do
        fields = ticket.extra_fields.to_h
        return if fields.dig("it_services_remote_support", "session_id").to_i >= room.id

        fields["it_services_remote_support"] = {
          "session_id" => room.id, "mode" => "attended_view_only", "requested_at" => room.created_at.iso8601,
          "consented_at" => room.consented_at&.iso8601, "display_reported_at" => room.display_reported_at&.iso8601,
          "ended_at" => room.ended_at.iso8601, "end_reason" => room.end_reason
        }
        ticket.update!(extra_fields: fields)
        ticket.log!(action: "it_services_screen_sharing_ended",
          detail: "Screen-sharing session ##{room.id} ended: #{room.end_reason}.", actor: User.find_by(id: actor_id))
      end
    end
  end
end
