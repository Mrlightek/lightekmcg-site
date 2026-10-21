# frozen_string_literal: true
require 'test_helper'

class NevaehTicketAuthenticatedHttpV2fTest < ActionDispatch::IntegrationTest
  PASSWORD = 'nevaeh-http-test-password'

  setup do
    Current.reset if Current.respond_to?(:reset)
  end

  teardown do
    Current.reset if Current.respond_to?(:reset)
  end

  def make_user(role)
    User.create!(
      email_address: "nevaeh-http-#{role}-#{SecureRandom.hex(7)}@example.test",
      first_name: 'Nevaeh', last_name: 'HTTP', role: role, password: PASSWORD
    )
  end

  def sign_in!(user)
    post session_path, params: { email_address: user.email_address, password: PASSWORD }
    assert_response :redirect
    assert Session.where(user_id: user.id).exists?, 'Expected real Rails Session created by POST /session'
  end

  def make_ticket
    Marlon::Ticket.create!(
      title: 'HTTP boundary ticket', category: Marlon::TicketCategories.ids.first,
      priority: 'medium', urgency: 5, status: 'open'
    )
  end

  test 'employee signs in and can create and reply without enqueuing work' do
    sign_in!(make_user('employee'))
    ticket_id = nil
    assert_difference 'Marlon::Ticket.count', +1 do
      assert_no_difference 'DymondDispatch::WorkItem.count' do
        post employee_tickets_path, params: {
          ticket: { title: 'Employee-created Nevaeh HTTP ticket',
            category: Marlon::TicketCategories.ids.first, priority: 'medium', urgency: 5 },
          work_order: { enabled: '0' }
        }
      end
      assert_response :redirect
      ticket_id = Marlon::Ticket.order(:id).last.id
    end
    t = Marlon::Ticket.find(ticket_id)
    assert_equal 'Employee-created Nevaeh HTTP ticket', t.title
    patch reply_employee_ticket_path(t), params: { detail: 'Employee permitted reply' }
    assert_response :redirect
    assert_equal 'in_progress', t.reload.status
    assert t.events.where('action LIKE ?', '%replied%').exists?
  end

  test 'employee cannot resolve a readable ticket' do
    t = make_ticket
    sign_in!(make_user('employee'))
    assert_no_difference 'DymondDispatch::WorkItem.count' do
      patch resolve_employee_ticket_path(t)
    end
    assert_response :redirect
    assert_equal 'open', t.reload.status
    assert_nil t.resolved_at
  end

  test 'employee cannot dispatch Nevaeh even with a readable ticket' do
    t = make_ticket
    sign_in!(make_user('employee'))
    assert_no_difference 'DymondDispatch::WorkItem.count' do
      post execute_nevaeh_employee_ticket_path(t)
    end
    assert_response :redirect
    assert_equal 'open', t.reload.status
    assert_nil t.extra_fields.to_h.dig('nevaeh', 'work_item_id')
  end

  test 'admin can resolve tickets through authenticated HTTP' do
    t = make_ticket
    sign_in!(make_user('admin'))
    patch resolve_employee_ticket_path(t)
    assert_response :redirect
    assert_equal 'resolved', t.reload.status
  end

  test 'admin reaches Nevaeh execution action but no work order fails closed' do
    t = make_ticket
    sign_in!(make_user('admin'))
    assert_no_difference 'DymondDispatch::WorkItem.count' do
      post execute_nevaeh_employee_ticket_path(t)
    end
    assert_response :redirect
    assert_nil t.reload.extra_fields.to_h.dig('nevaeh', 'work_item_id')
    assert_equal 'open', t.status
  end
end
