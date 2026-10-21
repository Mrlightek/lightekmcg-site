# frozen_string_literal: true
require 'test_helper'

class NevaehTicketAuthorizationV2cTest < ActiveSupport::TestCase
  def user(role = 'admin')
    User.create!(email_address: "v2c-#{SecureRandom.hex(8)}@example.test", first_name: 'Gate',
      last_name: 'Reviewer', role: role, password: 'temporary-test-password')
  end

  def ticket
    record = Marlon::Ticket.create!(title: 'V2C policy', category: Marlon::TicketCategories.ids.first,
      priority: 'medium', urgency: 5, status: 'open')
    order = NevaehIntelligences::WorkOrder.template.merge('objective' => 'Create reviewed Studio project',
      'inputs' => {'name' => 'V2C Proof'}, 'acceptance_criteria' => ['Persist and verify project'],
      'execution_policy' => {'environment' => 'production', 'approval' => 'gatekeeper'})
    NevaehIntelligences::WorkOrder.attach!(ticket: record, attributes: order)
    record
  end

  def approval(t, approver, scope: 'production_authorized')
    fp = NevaehIntelligences::TicketApproval.fingerprint(t.extra_fields['nevaeh_work_order'])
    reason = 'Administratively reviewed the precise production change'
    data = t.extra_fields.deep_dup
    data['nevaeh'] ||= {}
    data['nevaeh']['approval'] = {'status' => 'approved', 'fingerprint' => fp,
      'actor_id' => approver.id, 'approved_at' => Time.current.iso8601,
      'reason' => reason, 'scope' => scope}
    t.update!(extra_fields: data)
    t.log!(action: 'nevaeh_work_order_approved', actor: approver,
      detail: {fingerprint: fp, scope: scope, reason: reason}.to_json)
  end

  test 'V2B audit only approval never qualifies as production authorization' do
    t = ticket
    admin = user
    approval(t, admin, scope: 'audit_only_no_production_execution')
    assert_raises(NevaehIntelligences::TicketAuthorization::Denied) do
      NevaehIntelligences::TicketAuthorization.require_approved_revision!(ticket: t, actor: admin)
    end
  end

  test 'missing or mismatched event and edited work order fail closed' do
    t = ticket
    admin = user
    approval(t, admin)
    assert NevaehIntelligences::TicketAuthorization.require_approved_revision!(ticket: t, actor: admin)
    t.events.where(action: 'nevaeh_work_order_approved').delete_all
    assert_raises(NevaehIntelligences::TicketAuthorization::Denied) do
      NevaehIntelligences::TicketAuthorization.require_approved_revision!(ticket: t, actor: admin)
    end
    approval(t, admin)
    data = t.reload.extra_fields.deep_dup
    data['nevaeh_work_order']['inputs']['name'] = 'Altered'
    t.update!(extra_fields: data)
    assert_raises(NevaehIntelligences::TicketAuthorization::Denied) do
      NevaehIntelligences::TicketAuthorization.require_approved_revision!(ticket: t, actor: admin)
    end
  end

  test 'client or employee cannot authorize, and dispatch reservation blocks reuse' do
    t = ticket
    admin = user
    approval(t, admin)
    %w[employee client].each do |role|
      assert_raises(NevaehIntelligences::TicketAuthorization::Denied) do
        NevaehIntelligences::TicketAuthorization.require_approved_revision!(ticket: t, actor: user(role))
      end
    end
    data = t.extra_fields.deep_dup
    data['nevaeh']['execution_status'] = 'dispatch_reserved'
    t.update!(extra_fields: data)
    assert_raises(NevaehIntelligences::TicketAuthorization::Denied) do
      NevaehIntelligences::TicketAuthorization.require_approved_revision!(ticket: t, actor: admin)
    end
  end

  test 'production work order dispatch remains disabled even if approval checks pass' do
    t = ticket
    admin = user
    approval(t, admin)
    assert NevaehIntelligences::TicketAuthorization.require_approved_revision!(ticket: t, actor: admin)
    assert_raises(NevaehIntelligences::WorkOrder::Invalid) do
      NevaehIntelligences::WorkOrder.dispatch!(ticket: t, actor: admin)
    end
    assert_nil t.reload.extra_fields.dig('nevaeh', 'work_item_id')
  end
end
