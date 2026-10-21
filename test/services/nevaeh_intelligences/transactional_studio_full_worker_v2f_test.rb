# frozen_string_literal: true
require 'test_helper'
require 'securerandom'

# Exercises the installed DymondDispatch PerformWorkItemJob#perform entrypoint.
# Authorization is replaced ONLY inside these tests, to isolate the database
# execution guarantee; real Gatekeeper policy has its own persisted tests.
class TransactionalStudioFullWorkerV2fTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  def setup
    @reservation = "v2f6f-#{SecureRandom.uuid}"
    @work_item_ids = []
    @original_gate = NevaehIntelligences::ExecutionGateV2f.method(:require_allowed!)
    NevaehIntelligences::ExecutionGateV2f.define_singleton_method(:require_allowed!) { |_item| true }
    @ticket = Marlon::Ticket.create!(title: 'V2F6F full worker proof',
      category: Marlon::TicketCategories.ids.first, priority: 'medium', urgency: 5, status: 'open')
    @inputs = { 'name' => "V2F6F #{SecureRandom.hex(12)}", 'intent_key' => 'production', 'start_mode_key' => 'blank' }
    order = NevaehIntelligences::WorkOrder.template
    order['objective'] = 'Prove idempotency through actual worker'
    order['inputs'] = @inputs
    order['acceptance_criteria'] = ['Exactly one project']
    order['execution_policy']['environment'] = 'test'
    order = NevaehIntelligences::WorkOrder.validate!(order)
    fp = NevaehIntelligences::TicketApproval.method(:fingerprint)
    @ticket.update!(extra_fields: { 'nevaeh_work_order' => order,
      'nevaeh' => { 'reservation_id' => @reservation,
        'work_order_sha256' => fp.call(order), 'inputs_sha256' => fp.call(@inputs),
        'execution_status' => 'dispatch_reserved' } })
  end

  def teardown
    NevaehIntelligences::ExecutionGateV2f.define_singleton_method(:require_allowed!, @original_gate) if @original_gate
    return unless @ticket
    key = operation_key
    NevaehStudioIdempotencyRecord.where(operation_key: key).each do |receipt|
      StudioProject.where(id: receipt.studio_project_id).destroy_all
    end
    NevaehStudioIdempotencyRecord.where(operation_key: key).delete_all
    DymondDispatch::WorkItem.where(id: @work_item_ids).delete_all
    @ticket.destroy! if @ticket.persisted?
  end

  def operation_key
    "nevaeh:studio.project.create:ticket:#{@ticket.id}:reservation:#{@reservation}"
  end

  def work_item!
    item = DymondDispatch::WorkItem.create!(subject: @ticket,
      correlation_id: @reservation, kind: 'studio.project.create',
      handler: 'Studio::Workers::ProjectCreation', queue: 'default',
      status: 'queued', args: ['create', @inputs], dispositions: [])
    @work_item_ids << item.id
    item
  end

  test 'two distinct queued WorkItems converge through the real worker on one Studio result' do
    a, b = work_item!, work_item!
    before = StudioProject.count
    DymondDispatch::PerformWorkItemJob.new.perform(a.id)
    DymondDispatch::PerformWorkItemJob.new.perform(b.id)
    a.reload
    b.reload
    assert_equal 'done', a.status, a.error.to_s
    assert_equal 'done', b.status, b.error.to_s
    first = a.result.to_h.deep_stringify_keys
    second = b.result.to_h.deep_stringify_keys
    assert_equal first.fetch('project_id'), second.fetch('project_id')
    assert_equal true, second.fetch('idempotent_replay')
    assert_equal before + 1, StudioProject.count
    assert_equal 1, NevaehStudioIdempotencyRecord.where(operation_key: operation_key).count
    assert_equal 1, a.attempts
    assert_equal 1, b.attempts
  end

  test 'same WorkItem cannot be executed twice through the full worker' do
    a = work_item!
    job = DymondDispatch::PerformWorkItemJob.new
    job.perform(a.id)
    a.reload
    assert_equal 'done', a.status, a.error.to_s
    receipt_count = NevaehStudioIdempotencyRecord.where(operation_key: operation_key).count
    first_result = a.result
    job.perform(a.id)
    a.reload
    assert_equal 'done', a.status
    assert_equal 1, a.attempts
    assert_equal receipt_count, NevaehStudioIdempotencyRecord.where(operation_key: operation_key).count
    assert_equal first_result, a.result
  end

  test 'two threads with independent connections create only one logical project through full worker' do
    a, b = work_item!, work_item!
    before = StudioProject.count
    responses = Queue.new
    threads = [a.id, b.id].map do |id|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          begin
            DymondDispatch::PerformWorkItemJob.new.perform(id)
            responses << [:ok, id]
          rescue StandardError => error
            responses << [:error, "#{error.class}: #{error.message}"]
          end
        end
      end
    end
    threads.each { |t| assert t.join(20), 'worker thread timed out' }
    assert_equal [:ok, :ok], 2.times.map { responses.pop.first }.sort
    a.reload
    b.reload
    assert_equal 'done', a.status, a.error.to_s
    assert_equal 'done', b.status, b.error.to_s
    assert_equal a.result.to_h['project_id'], b.result.to_h['project_id']
    assert_equal before + 1, StudioProject.count
    assert_equal 1, NevaehStudioIdempotencyRecord.where(operation_key: operation_key).count
  end
end
