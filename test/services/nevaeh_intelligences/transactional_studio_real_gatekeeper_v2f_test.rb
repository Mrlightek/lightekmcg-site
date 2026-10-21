# frozen_string_literal: true
require 'test_helper'
require 'securerandom'

# Uses persisted administrator, ticket, capability, WorkOrder and WorkItem.
# No method stubs or Gatekeeper substitutions. Test DB only.
class TransactionalStudioRealGatekeeperV2fTest < ActiveSupport::TestCase
  self.use_transactional_tests = false
  CAPABILITY = 'studio.project.create'

  def setup
    @reservation = "v2f6h3-#{SecureRandom.uuid}"
    @work_items = []
    @admin = User.create!(email_address: "v2f6h3-#{SecureRandom.hex(8)}@example.test",
      first_name: 'V2F', last_name: 'Operator', role: 'admin', password: 'test-fixture-password')
    @capability = NevaehCapability.find_by(gatekeeper_capability: CAPABILITY) || NevaehCapability.find_by(slug: CAPABILITY)
    @created_capability = @capability.nil?
    @capability ||= NevaehCapability.create!(name: 'V2F6H3 test Studio capability', slug: CAPABILITY,
      domain: 'studio', intent_name: CAPABILITY, subject_type: 'Marlon::Ticket',
      handler: 'Studio::Workers::ProjectCreation', queue: 'default', priority: 2,
      gatekeeper_capability: CAPABILITY, enabled: true)
    @capability_was_enabled = @capability.enabled?
    @capability.update!(enabled: true) unless @capability.enabled?
    @ticket = Marlon::Ticket.create!(title: 'V2F6H3 real Gatekeeper worker proof',
      category: Marlon::TicketCategories.ids.first, priority: 'medium', urgency: 5, status: 'open')
    @inputs = { 'name' => "V2F6H3 #{SecureRandom.hex(12)}", 'intent_key' => 'production', 'start_mode_key' => 'blank' }
    order = NevaehIntelligences::WorkOrder.template
    order['objective'] = 'Verify real Gatekeeper worker execution'
    order['inputs'] = @inputs
    order['acceptance_criteria'] = ['One authorized Studio result']
    order['execution_policy']['environment'] = 'test'
    order = NevaehIntelligences::WorkOrder.validate!(order)
    fingerprint = NevaehIntelligences::TicketApproval.method(:fingerprint)
    @ticket.update!(extra_fields: { 'nevaeh_work_order' => order,
      'nevaeh' => {'reservation_id' => @reservation, 'actor_id' => @admin.id,
        'work_order_sha256' => fingerprint.call(order), 'inputs_sha256' => fingerprint.call(@inputs),
        'execution_status' => 'dispatch_reserved'} })
  end

  def operation_key
    "nevaeh:studio.project.create:ticket:#{@ticket.id}:reservation:#{@reservation}"
  end

  def create_item
    item = DymondDispatch::WorkItem.create!(subject: @ticket, correlation_id: @reservation,
      kind: CAPABILITY, handler: 'Studio::Workers::ProjectCreation', queue: 'default',
      status: 'queued', args: ['create', @inputs], dispositions: [])
    @work_items << item
    item
  end

  def run_worker(item)
    DymondDispatch::PerformWorkItemJob.new.perform(item.id)
    item.reload
  end

  def assert_denied_without_mutation(item)
    before_projects = StudioProject.count
    before_receipts = NevaehStudioIdempotencyRecord.count
    run_worker(item)
    assert_equal 'failed', item.status, item.error.to_s
    assert_equal before_projects, StudioProject.count
    assert_equal before_receipts, NevaehStudioIdempotencyRecord.count
  end

  test 'real Gatekeeper permits authorized Studio creation and receipt' do
    item = create_item
    count = StudioProject.count
    run_worker(item)
    assert_equal 'done', item.status, item.error.to_s
    assert_equal count + 1, StudioProject.count
    receipt = NevaehStudioIdempotencyRecord.find_by!(operation_key: operation_key)
    assert_equal item.id, receipt.work_item_id
    assert_equal item.result.to_h.deep_stringify_keys.fetch('project_id').to_s, receipt.studio_project_id.to_s
    assert_equal 'open', @ticket.reload.status
  end

  test 'real Gatekeeper denies capability revocation before worker execution' do
    @capability.update!(enabled: false)
    assert_denied_without_mutation(create_item)
  end

  test 'real Gatekeeper denies missing original actor' do
    fields = @ticket.extra_fields.to_h.deep_stringify_keys
    fields.fetch('nevaeh')['actor_id'] = -999_999
    @ticket.update!(extra_fields: fields)
    assert_denied_without_mutation(create_item)
  end

  test 'real Gatekeeper denies tampered work order revision' do
    fields = @ticket.extra_fields.to_h.deep_stringify_keys
    fields.fetch('nevaeh')['work_order_sha256'] = '0' * 64
    @ticket.update!(extra_fields: fields)
    assert_denied_without_mutation(create_item)
  end

  def teardown
    if @ticket
      NevaehStudioIdempotencyRecord.where(operation_key: operation_key).each do |receipt|
        StudioProject.where(id: receipt.studio_project_id).destroy_all
      end
      NevaehStudioIdempotencyRecord.where(operation_key: operation_key).delete_all
    end
    @work_items&.each { |item| item.destroy! if item.persisted? }
    @ticket&.destroy! if @ticket&.persisted?
    if @capability&.persisted?
      if @created_capability
        @capability.destroy!
      elsif !@capability_was_enabled.nil? && @capability.reload.enabled? != @capability_was_enabled
        @capability.update!(enabled: @capability_was_enabled)
      end
    end
    @admin&.destroy! if @admin&.persisted?
  end
end
