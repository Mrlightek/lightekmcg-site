# frozen_string_literal: true
module NevaehIntelligences
  module TicketDraftAccessV7a
    module_function
    def allowed?
      Rails.env.test? || (Rails.env.development? && ENV["NEVAEH_LOCAL_TICKET_DRAFTS"] == "1")
    end
  end
end
