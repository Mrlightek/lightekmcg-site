# frozen_string_literal: true
require 'test_helper'

class NevaehAuthenticationV2bTest < ActionDispatch::IntegrationTest
  test 'anonymous ticket execution does not dispatch any work' do
    t = Marlon::Ticket.create!(title: 'Anonymous dispatch rejection',
      category: Marlon::TicketCategories.ids.first, priority: 'medium', urgency: 5, status: 'open')
    assert_no_difference 'DymondDispatch::WorkItem.count' do
      post execute_nevaeh_employee_ticket_path(t)
    end
    assert_response :redirect
    assert_equal 'open', t.reload.status
    assert_nil t.extra_fields.to_h.dig('nevaeh', 'work_item_id')
  end
end
