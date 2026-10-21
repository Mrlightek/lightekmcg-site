# frozen_string_literal: true
require 'test_helper'

class NevaehTicketOperatorPermissionsV2fTest < ActiveSupport::TestCase
  test 'employees may read create and reply but cannot resolve or execute' do
    ability = Ability.new(User.new(role: 'employee'))
    ticket = Marlon::Ticket.new
    assert ability.can?(:read, ticket)
    assert ability.can?(:create, Marlon::Ticket)
    assert ability.can?(:reply, ticket)
    assert ability.cannot?(:resolve, ticket)
    assert ability.cannot?(:execute_nevaeh, ticket)
    assert ability.cannot?(:update, ticket)
  end

  test 'admins can create reply resolve and execute' do
    ability = Ability.new(User.new(role: 'admin'))
    ticket = Marlon::Ticket.new
    assert ability.can?(:create, Marlon::Ticket)
    assert ability.can?(:reply, ticket)
    assert ability.can?(:resolve, ticket)
    assert ability.can?(:execute_nevaeh, ticket)
  end

  test 'guest cannot create reply resolve or execute tickets' do
    ability = Ability.new(User.new)
    ticket = Marlon::Ticket.new
    assert ability.cannot?(:create, Marlon::Ticket)
    assert ability.cannot?(:reply, ticket)
    assert ability.cannot?(:resolve, ticket)
    assert ability.cannot?(:execute_nevaeh, ticket)
  end
end
