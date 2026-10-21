# frozen_string_literal: true
require 'test_helper'
require 'securerandom'

# Exercises real Rails session cookies, controller authorization, Gatekeeper,
# intelligence registry, Nevaeh.handle and DymondDispatch dispatch. The
# background worker is NOT performed in this HTTP test.
class NevaehTicketAdminDispatchHttpV2fTest < ActionDispatch::IntegrationTest
  PASSWORD = 'v2f6j11d-test-password'
  CAP = 'studio.project.create'

  setup do
    Current.reset if Current.respond_to?(:reset)
    # Do not silently change or enable existing test registry records.
    @capability = NevaehCapability.find_by(gatekeeper_capability: CAP) || NevaehCapability.find_by(slug: CAP)
    if @capability
      assert @capability.enabled?, 'STOP: existing capability disabled'
      assert_equal CAP, @capability.slug
      assert_equal 'Marlon::Ticket', @capability.subject_type
      assert_equal 'Studio::Workers::ProjectCreation', @capability.handler
      assert @capability.event_types.include?('studio.project.create.requested'), 'STOP: event type mismatch'
    else
      @capability = NevaehCapability.create!(name:'V2F6J11D test capability',slug:CAP,
        domain:'studio',intent_name:CAP,subject_type:'Marlon::Ticket',
        handler:'Studio::Workers::ProjectCreation',queue:'default',priority:2,
        gatekeeper_capability:CAP,event_types:['studio.project.create.requested'],enabled:true)
    end
    @intelligence = NevaehIntelligence.find_by(intent_key: CAP)
    if @intelligence
      assert_equal @capability.id, @intelligence.nevaeh_capability_id, 'STOP: intelligence capability mismatch'
      assert NevaehIntelligence.available.where(id:@intelligence.id).exists?, 'STOP: existing intelligence unavailable'
      assert_equal 'create', @intelligence.dispatch_action
    else
      @intelligence = NevaehIntelligence.create!(name:'V2F6J11D test intelligence',intent_key:CAP,
        nevaeh_capability:@capability,status:'published',operation:'create',
        execution_mode:'async',target_model:'StudioProject',instructions:{'action'=>'create'})
      assert NevaehIntelligence.available.where(id:@intelligence.id).exists?
    end
    @admin=User.create!(email_address:"v2f6j11d-#{SecureRandom.hex(10)}@example.test",
      first_name:'Release',last_name:'Proof',role:'admin',password:PASSWORD)
    @ticket=Marlon::Ticket.create!(title:'V2F6J11D admin HTTP proof',
      category:Marlon::TicketCategories.ids.first,priority:'medium',urgency:5,status:'open',submitted_by:@admin)
    @name="V2F6J11D #{SecureRandom.hex(10)}"
    order=NevaehIntelligences::WorkOrder.template
    order['objective']='Verify authorized HTTP dispatch with real Gatekeeper'
    order['inputs']={'name'=>@name,'intent_key'=>'production','start_mode_key'=>'blank'}
    order['acceptance_criteria']=['WorkItem and ticket receipt saved']
    order['execution_policy']['environment']='test'
    NevaehIntelligences::WorkOrder.attach!(ticket:@ticket,attributes:order)
  end

  teardown { Current.reset if Current.respond_to?(:reset) }

  test 'authenticated admin dispatch creates linked queued work without running Studio worker' do
    assert Rails.env.test?
    post session_path, params:{email_address:@admin.email_address,password:PASSWORD}
    assert_response :redirect
    assert Session.where(user_id:@admin.id).exists?
    before_projects=StudioProject.count
    before_receipts=NevaehStudioIdempotencyRecord.count
    assert_difference 'DymondDispatch::WorkItem.count', 1 do
      post execute_nevaeh_employee_ticket_path(@ticket)
    end
    assert_response :redirect
    state=@ticket.reload.extra_fields.to_h.deep_stringify_keys.fetch('nevaeh')
    assert_equal 'dispatched',state.fetch('execution_status')
    assert_equal @admin.id.to_s,state.fetch('actor_id').to_s
    item=DymondDispatch::WorkItem.find(state.fetch('work_item_id'))
    assert_equal CAP,item.kind
    assert_equal 'Marlon::Ticket',item.subject_type
    assert_equal @ticket.id,item.subject_id
    assert_equal state.fetch('correlation_id'),item.correlation_id
    assert_equal 'Studio::Workers::ProjectCreation',item.handler
    assert_equal before_projects,StudioProject.count,'worker must not run inline in this HTTP test'
    assert_equal before_receipts,NevaehStudioIdempotencyRecord.count
    assert @ticket.events.where(action:'nevaeh_dispatched').exists?
  end
end
