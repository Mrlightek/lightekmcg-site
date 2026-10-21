# frozen_string_literal: true
require 'test_helper'
require 'securerandom'

class TransactionalStudioWorkerDenialV2fTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  def setup
    @reservation = "v2f6h2-#{SecureRandom.uuid}"
    @original_gate = NevaehIntelligences::ExecutionGateV2f.method(:require_allowed!)
    @ticket = Marlon::Ticket.create!(title: 'V2F6H2 worker authorization denial',
      category: Marlon::TicketCategories.ids.first, priority: 'medium', urgency: 5, status: 'open')
    @inputs = { 'name' => "V2F6H2 #{SecureRandom.hex(12)}", 'intent_key' => 'production', 'start_mode_key' => 'blank' }
    order = NevaehIntelligences::WorkOrder.template
    order['objective'] = 'Deny mutation through complete worker'
    order['inputs'] = @inputs
    order['acceptance_criteria'] = ['No Studio mutation after denial']
    order['execution_policy']['environment'] = 'test'
    order = NevaehIntelligences::WorkOrder.validate!(order)
    fp = NevaehIntelligences::TicketApproval.method(:fingerprint)
    @ticket.update!(extra_fields: { 'nevaeh_work_order' => order,
      'nevaeh' => { 'reservation_id' => @reservation,
        'work_order_sha256' => fp.call(order), 'inputs_sha256' => fp.call(@inputs),
        'execution_status' => 'dispatch_reserved' } })
    @item = DymondDispatch::WorkItem.create!(subject: @ticket, correlation_id: @reservation,
      kind: 'studio.project.create', handler: 'Studio::Workers::ProjectCreation',
      queue: 'default', status: 'queued', args: ['create', @inputs], dispositions: [])
  end

  def teardown
    NevaehIntelligences::ExecutionGateV2f.define_singleton_method(:require_allowed!, @original_gate) if @original_gate
    if @ticket
      key = "nevaeh:studio.project.create:ticket:#{@ticket.id}:reservation:#{@reservation}"
      NevaehStudioIdempotencyRecord.where(operation_key: key).each { |r| StudioProject.where(id: r.studio_project_id).destroy_all }
      NevaehStudioIdempotencyRecord.where(operation_key: key).delete_all
    end
    @item.destroy! if @item&.persisted?
    @ticket.destroy! if @ticket&.persisted?
  end

  test 'denial inside transactional invoke blocks Studio mutation through worker perform' do
    gate_calls = Queue.new
    NevaehIntelligences::ExecutionGateV2f.define_singleton_method(:require_allowed!) do |item|
      gate_calls << item.id
      raise NevaehIntelligences::TransactionalStudioCreationV2f::Denied, 'denied by V2F6H2 test'
    end
    before_projects = StudioProject.count
    before_receipts = NevaehStudioIdempotencyRecord.count
    DymondDispatch::PerformWorkItemJob.new.perform(@item.id)
    @item.reload
    assert_equal 'failed', @item.status
    assert_equal @item.id, gate_calls.pop
    assert gate_calls.empty?, 'Expected exactly one in-transaction authorization call'
    assert_equal before_projects, StudioProject.count
    assert_equal before_receipts, NevaehStudioIdempotencyRecord.count
  end
end
