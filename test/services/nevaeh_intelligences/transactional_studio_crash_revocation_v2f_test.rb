# frozen_string_literal: true
require 'test_helper'
require 'securerandom'

# Tests deliberately bypass authorization only to isolate database failure timing.
# Denial tests replace Gatekeeper with a strictly denying implementation.
# They do not establish real simultaneous policy-revocation atomicity.
class TransactionalStudioCrashRevocationV2fTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  def setup
    @reservation = "v2f6g-#{SecureRandom.uuid}"
    @work_item_ids = []
    @project_ids = []
    @original_gate = NevaehIntelligences::ExecutionGateV2f.method(:require_allowed!)
    @ticket = Marlon::Ticket.create!(title: 'V2F6G interruption proof',
      category: Marlon::TicketCategories.ids.first, priority: 'medium', urgency: 5, status: 'open')
    @inputs = {'name' => "V2F6G #{SecureRandom.hex(12)}", 'intent_key' => 'production', 'start_mode_key' => 'blank'}
    order = NevaehIntelligences::WorkOrder.template
    order['objective'] = 'Verify interrupted worker behavior'
    order['inputs'] = @inputs
    order['acceptance_criteria'] = ['Single durable creation']
    order['execution_policy']['environment'] = 'test'
    order = NevaehIntelligences::WorkOrder.validate!(order)
    fingerprint = NevaehIntelligences::TicketApproval.method(:fingerprint)
    @ticket.update!(extra_fields: {'nevaeh_work_order' => order,
      'nevaeh' => {'reservation_id' => @reservation,
        'work_order_sha256' => fingerprint.call(order),
        'inputs_sha256' => fingerprint.call(@inputs),
        'execution_status' => 'dispatch_reserved'}})
  end

  def teardown
    NevaehIntelligences::ExecutionGateV2f.define_singleton_method(:require_allowed!, @original_gate) if @original_gate
    return unless @ticket
    receipts = NevaehStudioIdempotencyRecord.where(operation_key: operation_key).to_a
    @project_ids.concat(receipts.map(&:studio_project_id))
    @project_ids.uniq.each { |id| StudioProject.where(id: id).destroy_all }
    NevaehStudioIdempotencyRecord.where(operation_key: operation_key).delete_all
    DymondDispatch::WorkItem.where(id: @work_item_ids).delete_all
    @ticket.destroy! if @ticket.persisted?
  end

  def operation_key
    "nevaeh:studio.project.create:ticket:#{@ticket.id}:reservation:#{@reservation}"
  end

  def gate_allow!
    NevaehIntelligences::ExecutionGateV2f.define_singleton_method(:require_allowed!) { |_item| true }
  end

  def gate_deny!
    NevaehIntelligences::ExecutionGateV2f.define_singleton_method(:require_allowed!) do |_item|
      raise NevaehIntelligences::TransactionalStudioCreationV2f::Denied, 'revoked in test'
    end
  end

  def item!(status: 'working')
    item = DymondDispatch::WorkItem.create!(subject: @ticket,
      correlation_id: @reservation, kind: 'studio.project.create',
      handler: 'Studio::Workers::ProjectCreation', queue: 'default',
      status: status, args: ['create', @inputs], dispositions: [])
    @work_item_ids << item.id
    item
  end

  test 'authorization denial before first mutation writes nothing' do
    item = item!
    gate_deny!
    baseline = StudioProject.count
    assert_raises(NevaehIntelligences::TransactionalStudioCreationV2f::Denied) do
      NevaehIntelligences::TransactionalStudioCreationV2f.call(item: item)
    end
    assert_equal baseline, StudioProject.count
    assert_equal 0, NevaehStudioIdempotencyRecord.where(operation_key: operation_key).count
  end

  test 'revocation after completed receipt blocks even replay of recorded result' do
    gate_allow!
    original = item!
    first = NevaehIntelligences::TransactionalStudioCreationV2f.call(item: original)
    @project_ids << first.fetch('project_id')
    replay = item!
    gate_deny!
    baseline = StudioProject.count
    assert_raises(NevaehIntelligences::TransactionalStudioCreationV2f::Denied) do
      NevaehIntelligences::TransactionalStudioCreationV2f.call(item: replay)
    end
    assert_equal baseline, StudioProject.count
    assert_equal 1, NevaehStudioIdempotencyRecord.where(operation_key: operation_key).count
  end

  test 'failure writing receipt rolls back Studio creation and permits later safe attempt' do
    gate_allow!
    first = item!
    baseline = StudioProject.count
    klass = NevaehStudioIdempotencyRecord
    original = klass.method(:create!)
    begin
      klass.define_singleton_method(:create!) { |**_attributes| raise 'v2f6g simulated receipt failure' }
      assert_raises(RuntimeError) { NevaehIntelligences::TransactionalStudioCreationV2f.call(item: first) }
    ensure
      klass.define_singleton_method(:create!, original)
    end
    assert_equal baseline, StudioProject.count
    assert_equal 0, klass.where(operation_key: operation_key).count
    second = item!
    result = NevaehIntelligences::TransactionalStudioCreationV2f.call(item: second)
    @project_ids << result.fetch('project_id')
    assert_equal baseline + 1, StudioProject.count
    assert_equal 1, klass.where(operation_key: operation_key).count
  end

  test 'committed Studio receipt survives missing WorkItem completion and later worker resumes idempotently' do
    gate_allow!
    abandoned = item!
    initial = NevaehIntelligences::TransactionalStudioCreationV2f.call(item: abandoned)
    @project_ids << initial.fetch('project_id')
    assert_equal 'working', abandoned.reload.status
    baseline = StudioProject.count
    fresh = item!(status: 'queued')
    DymondDispatch::PerformWorkItemJob.new.perform(fresh.id)
    assert_equal 'done', fresh.reload.status, fresh.error.to_s
    assert_equal initial.fetch('project_id'), fresh.result.to_h.deep_stringify_keys.fetch('project_id')
    assert_equal true, fresh.result.to_h.deep_stringify_keys.fetch('idempotent_replay')
    assert_equal baseline, StudioProject.count
    assert_equal 1, NevaehStudioIdempotencyRecord.where(operation_key: operation_key).count
    assert_equal 'working', abandoned.reload.status
  end
end
