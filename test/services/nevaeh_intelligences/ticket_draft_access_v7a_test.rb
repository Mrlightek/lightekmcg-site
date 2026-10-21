# frozen_string_literal: true
require "test_helper"
class TicketDraftAccessV7aTest < ActiveSupport::TestCase
  test "test environment permits existing ticket regression" do
    assert Rails.env.test?
    assert NevaehIntelligences::TicketDraftAccessV7a.allowed?
  end
  test "no code promotion or execution API is added to the access contract" do
    refute NevaehIntelligences::TicketDraftAccessV7a.respond_to?(:execute)
    refute NevaehIntelligences::TicketDraftAccessV7a.respond_to?(:promote)
  end
end
