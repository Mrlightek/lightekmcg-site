# frozen_string_literal: true
class RegisterStructuredTicketExecution < ActiveRecord::Migration[8.0]
  def up
    capability = NevaehIntelligences::StructuredTicket.registered!
    # Only temporary native-acceptance registrations are activated here.
    # Preserve an operator's independently disabled capability.
    if capability.metadata.to_h["acceptance_only"] == true
      capability.update!(enabled: true, queue: "default", metadata: capability.metadata.except("acceptance_only"))
    end
  end

  def down
    NevaehCapability.find_by(slug: "ticket.structured.execute")&.update!(enabled: false)
  end
end
