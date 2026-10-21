# frozen_string_literal: true
require "test_helper"

class NevaehTicketExecutionTest < ActiveSupport::TestCase
  test "rejects an unassigned ticket without dispatch" do
    ticket = Marlon::Ticket.new(status: "open", extra_fields: {})
    assert_raises(NevaehIntelligences::TicketExecution::InvalidTicket) do
      NevaehIntelligences::TicketExecution.dispatch!(ticket: ticket, actor: nil, payload: {name: "test"})
    end
  end


end
