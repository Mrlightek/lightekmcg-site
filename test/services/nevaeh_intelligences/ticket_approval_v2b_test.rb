# frozen_string_literal: true
require 'test_helper'

class NevaehTicketApprovalV2bTest < ActiveSupport::TestCase
  def actor(role = 'admin')
    User.create!(email_address: "v2b-#{SecureRandom.hex(8)}@example.test",
      first_name: 'Work', last_name: 'Reviewer', role: role, password: 'temporary-test-password')
  end

  def ticket
    t = Marlon::Ticket.create!(title: 'Approval V2B', category: Marlon::TicketCategories.ids.first,
      priority: 'medium', urgency: 5, status: 'open')
    order = NevaehIntelligences::WorkOrder.template.merge(
      'objective' => 'Create a verified project',
      'inputs' => {'name' => 'Approved Project'},
      'acceptance_criteria' => ['Persist project and production'])
    NevaehIntelligences::WorkOrder.attach!(ticket: t, attributes: order)
    t
  end

  test 'admin approval creates one audit event for exact persisted revision' do
    t = ticket
    admin = actor
    receipt = NevaehIntelligences::TicketApproval.approve!(ticket: t, actor: admin, reason: 'Reviewed scope and verified input controls')
    assert_equal admin.id, receipt['actor_id']
    assert NevaehIntelligences::TicketApproval.approved_revision?(ticket: t.reload)
    assert_equal 1, t.events.where(action: 'nevaeh_work_order_approved').count
    assert_raises(NevaehIntelligences::TicketApproval::Denied) { NevaehIntelligences::TicketApproval.approve!(ticket: t, actor: admin, reason: 'Another approval attempt') }
  end

  test 'ordinary employee and client cannot approve' do
    t = ticket
    %w[employee client].each do |role|
      assert_raises(NevaehIntelligences::TicketApproval::Denied) do
        NevaehIntelligences::TicketApproval.approve!(ticket: t, actor: actor(role), reason: 'Trying to authorize production work')
      end
    end
    assert_equal 0, t.events.where(action: 'nevaeh_work_order_approved').count
  end

  test 'approval does not survive changes to the saved work order' do
    t = ticket
    NevaehIntelligences::TicketApproval.approve!(ticket: t, actor: actor, reason: 'Verified existing project request')
    data = t.reload.extra_fields.deep_dup
    data['nevaeh_work_order']['inputs']['name'] = 'Changed Project'
    t.update!(extra_fields: data)
    refute NevaehIntelligences::TicketApproval.approved_revision?(ticket: t.reload)
  end

  test 'missing work order, short reason, and reserved ticket are rejected' do
    t = ticket
    admin = actor
    assert_raises(NevaehIntelligences::TicketApproval::Denied) { NevaehIntelligences::TicketApproval.approve!(ticket: t, actor: admin, reason: 'short') }
    data = t.extra_fields.deep_dup
    data['nevaeh'] ||= {}
    data['nevaeh']['execution_status'] = 'dispatch_reserved'
    t.update!(extra_fields: data)
    assert_raises(NevaehIntelligences::TicketApproval::Denied) { NevaehIntelligences::TicketApproval.approve!(ticket: t, actor: admin, reason: 'Approval after execution reservation') }
  end

  test 'hash key order does not change work order fingerprint' do
    one = {'a' => {'x' => 1, 'y' => 2}, 'b' => [3, 4]}
    two = {'b' => [3, 4], 'a' => {'y' => 2, 'x' => 1}}
    assert_equal NevaehIntelligences::TicketApproval.fingerprint(one), NevaehIntelligences::TicketApproval.fingerprint(two)
  end
end
