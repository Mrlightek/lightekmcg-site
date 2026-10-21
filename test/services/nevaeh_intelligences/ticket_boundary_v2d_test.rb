# frozen_string_literal: true

require "test_helper"

class NevaehTicketBoundaryV2dTest < ActiveSupport::TestCase
  test "direct dispatch cannot run without a persisted ticket" do
    actor = User.new(role: "employee")
    error = assert_raises(NevaehIntelligences::TicketExecution::InvalidTicket) do
      NevaehIntelligences::TicketExecution.dispatch!(ticket: Marlon::Ticket.new, actor: actor, payload: {"name" => "x"})
    end
    assert_match(/Authenticated employee/, error.message)
  end

  test "direct dispatch rejects an unauthenticated caller without queueing" do
    error = assert_raises(NevaehIntelligences::TicketExecution::InvalidTicket) do
      NevaehIntelligences::TicketExecution.dispatch!(ticket: Marlon::Ticket.new, actor: nil, payload: {"name" => "x"})
    end
    assert_match(/Authenticated employee/, error.message)
  end

  test "direct dispatch rejects an unauthorized client" do
    actor = User.new(role: "client")
    error = assert_raises(NevaehIntelligences::TicketExecution::InvalidTicket) do
      NevaehIntelligences::TicketExecution.dispatch!(ticket: Marlon::Ticket.new, actor: actor, payload: {"name" => "x"})
    end
    assert_match(/Authenticated employee/, error.message)
  end
end
