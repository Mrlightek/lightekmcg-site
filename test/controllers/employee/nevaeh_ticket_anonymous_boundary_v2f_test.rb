# frozen_string_literal: true
require 'test_helper'

class NevaehTicketAnonymousBoundaryV2fTest < ActionDispatch::IntegrationTest
  test 'anonymous ticket creation does not persist tickets or dispatch work' do
    assert_no_difference ['Marlon::Ticket.count', 'DymondDispatch::WorkItem.count'] do
      post employee_tickets_path, params: {
        ticket: {title: 'Anonymous request rejected', category: Marlon::TicketCategories.ids.first,
                 priority: 'medium', urgency: 5},
        work_order: {enabled: '1', work_type: 'create', intent_key: 'studio.project.create',
                     objective: 'This must not run'}
      }
    end
    assert_response :redirect
  end

  test 'anonymous dispatch route does not enqueue work' do
    assert_no_difference 'DymondDispatch::WorkItem.count' do
      post execute_nevaeh_employee_ticket_path(id: 999999991)
    end
    assert_response :redirect
  end
end
