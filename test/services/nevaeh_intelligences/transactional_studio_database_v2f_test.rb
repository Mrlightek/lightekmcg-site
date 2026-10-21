# frozen_string_literal: true
require 'test_helper'
require 'securerandom'
require 'digest'
require 'json'

# Real PostgreSQL transactions, real Studio creation and real WorkItems.
# Test-only authorization substitution isolates DB idempotency, not Gatekeeper policy.
class TransactionalStudioDatabaseV2fTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  def setup
    @created = []
    @original_gate = NevaehIntelligences::ExecutionGateV2f.method(:require_allowed!)
    NevaehIntelligences::ExecutionGateV2f.define_singleton_method(:require_allowed!) { |_item| true }
    @reservation = "v2f6d-#{SecureRandom.uuid}"
    @ticket = Marlon::Ticket.create!(title: 'V2F6D isolated idempotency proof',
      category: Marlon::TicketCategories.ids.first, priority: 'medium', urgency: 5, status: 'open')
    @created << @ticket
    @inputs = {'name' => "V2F6D #{SecureRandom.hex(12)}", 'intent_key' => 'production', 'start_mode_key' => 'blank'}
    order = NevaehIntelligences::WorkOrder.template
    order['objective'] = 'Prove transactional idempotency without dispatch'
    order['inputs'] = @inputs
    order['acceptance_criteria'] = ['Exactly one project']
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
    # Explicit cleanup because concurrent connections cannot use transactional fixtures.
    if @ticket
      key = "nevaeh:studio.project.create:ticket:#{@ticket.id}:reservation:#{@reservation}"
      receipts = NevaehStudioIdempotencyRecord.where(operation_key: key).to_a
      receipts.each do |r|
        StudioProject.where(id: r.studio_project_id).destroy_all
      end
      NevaehStudioIdempotencyRecord.where(operation_key: key).delete_all
      DymondDispatch::WorkItem.where(id: @created.grep(DymondDispatch::WorkItem).map(&:id)).delete_all
      @ticket.destroy! if @ticket.persisted?
    end
  end

  def item!
    item = DymondDispatch::WorkItem.create!(subject: @ticket, correlation_id: @reservation,
      kind: 'studio.project.create', handler: 'Studio::Workers::ProjectCreation',
      queue: 'default', status: 'working', args: ['create', @inputs])
    @created << item
    item
  end

  def operation_key
    "nevaeh:studio.project.create:ticket:#{@ticket.id}:reservation:#{@reservation}"
  end

  test 'unique index blocks duplicate logical operation receipts' do
    assert ActiveRecord::Base.connection.indexes('nevaeh_studio_idempotency_records').any? { |i| i.unique && i.columns == ['operation_key'] }
  end

  test 'two distinct WorkItems reuse one committed Studio result' do
    first = item!
    second = item!
    first_result = NevaehIntelligences::TransactionalStudioCreationV2f.call(item: first)
    second_result = NevaehIntelligences::TransactionalStudioCreationV2f.call(item: second)
    assert_equal first_result.fetch('project_id'), second_result.fetch('project_id')
    assert_equal true, second_result.fetch('idempotent_replay')
    assert_equal 1, NevaehStudioIdempotencyRecord.where(operation_key: operation_key).count
    assert_equal 1, StudioProject.where(id: first_result.fetch('project_id')).count
  end

  test 'rollback after Studio mutation does not leave committed receipt or project' do
    item = item!
    records = NevaehStudioIdempotencyRecord
    original = records.method(:create!)
    records.define_singleton_method(:create!) { |**_kwargs| raise ActiveRecord::Rollback, 'deliberate pre-receipt abort' }
    count_before = StudioProject.count
    NevaehIntelligences::TransactionalStudioCreationV2f.call(item: item)
    assert_equal count_before, StudioProject.count
    assert_equal 0, records.where(operation_key: operation_key).count
  ensure
    records.define_singleton_method(:create!, original) if records && original
  end

  test 'concurrent distinct WorkItems use independent PostgreSQL connections and one result' do
    first, second = item!, item!
    results = Queue.new
    workers = [first.id, second.id].map do |id|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          begin
            result = NevaehIntelligences::TransactionalStudioCreationV2f.call(item: DymondDispatch::WorkItem.find(id))
            results << [:ok, result]
          rescue StandardError => error
            results << [:error, error.class.name + ': ' + error.message]
          end
        end
      end
    end
    workers.each { |w| assert w.join(20), 'worker did not complete within 20 seconds' }
    output = 2.times.map { results.pop }
    assert_equal [:ok, :ok], output.map(&:first)
    assert_equal 1, output.map { |x| x.last.fetch('project_id') }.uniq.length
    assert_equal 1, NevaehStudioIdempotencyRecord.where(operation_key: operation_key).count
  end
end
