require_relative 'nevaeh_workforce_goal_checks'
class NevaehPageWorkerChecks < NevaehOsTest
  def self.runnable_methods = instance_methods(false).grep(/^test_/).map(&:to_s)
  def setup
    super
    @site=DymondSite::Site.create!(host:'page.test')
    @context={'path'=>'/dashboard/mail','site_id'=>@site.id.to_s,'title'=>'Communications'}
    @cap=NevaehCapability.create!(slug:'messages.list',name:'List conversations',domain:'messages',intent_name:'messages_list',handler:'Messaging::Worker',queue:'default',priority:5,event_types:['messages.list.requested'])
  end
  def task
    NevaehOs::PageWorkers.manifest(@actor,@context)[:actions].find { |row| row[:key]=='messages.list' }
  end
  def ask(page_action:nil,mode:'operate',key:SecureRandom.uuid)
    NevaehOs::Conversation.new(actor:@actor,host:'page.test').ask(text:'show messages',request_key:key,page_context:@context,page_action:page_action,mode:mode)
  end
  def test_page_contract_uses_actual_inputs_current_application_and_mail_specialist
    row=task
    assert_equal 'mail',row[:worker][:key]
    assert_equal @site.id.to_s,row[:defaults]['site_id']
    assert_equal ['site_id'],row[:inputs].keys
    assert_match(/\A[0-9a-f]{64}\z/,row[:fingerprint])
    assert_equal 'docs/nevaeh/tutorials/platform.md',row[:source][:path]
    other_context=@context.merge('path'=>'/dashboard/bank')
    refute NevaehOs::PageWorkers.manifest(@actor,other_context)[:actions].any? { |item| item[:key]=='messages.list' }
  end
  def test_manager_delegates_to_reusable_page_worker_and_follows_downstream_receipt
    result=ask
    manager=NevaehOsAction.find(result['action_id'])
    assert_equal 'agent_task',manager.command['kind']
    execute(manager)
    worker=NevaehAgentWorker.last
    assert_equal 'mail',worker.nevaeh_os_agent.system_key
    assert_equal @context['path'],worker.command.dig('page_contract','context','path')
    run=worker.runs.last
    NevaehOs::AgentWorkforce.execute!(run)
    child=run.reload.nevaeh_os_action
    execute(child)
    service_item=DymondDispatch::WorkItem.find(child.reload.result['work_item_id'])
    assert_equal @actor.id,service_item.args[1]['actor_id']
    assert_equal @site.id,service_item.args[1]['site_id']
    refute_equal 'completed',NevaehOs::Receipts.for(manager.reload)[:status]
    service_item.update!(status:'done',result:{'messages'=>[]})
    assert_equal 'completed',NevaehOs::Receipts.for(manager.reload)[:status]
    next_result=ask
    execute(NevaehOsAction.find(next_result['action_id']))
    assert_equal 1,NevaehAgentWorker.where(nevaeh_os_agent:worker.nevaeh_os_agent).count
    assert_equal 2,worker.runs.count
  end
  def test_missing_inputs_are_requested_without_dispatch_and_types_and_scope_are_enforced
    @cap.update!(slug:'messages.show',name:'Open conversation',metadata:{'input_schema'=>{'conversation_id'=>'integer'}})
    row=NevaehOs::PageWorkers.manifest(@actor,@context)[:actions].find { |item| item[:key]=='messages.show' }
    assert row[:inputs]['conversation_id']['required']
    payload={key:row[:key],fingerprint:row[:fingerprint],inputs:{'conversation_id'=>'not-a-number'}}
    assert_raises(ArgumentError) { ask(page_action:payload) }
    payload[:inputs]={'conversation_id'=>'2','site_id'=>(@site.id+1).to_s}
    assert_raises(ArgumentError) { ask(page_action:payload) }
    assert_equal 0,NevaehOsAction.count
    @cap.update!(slug:'studio.project.create',name:'Create Studio project',domain:'studio')
    context=@context.merge('path'=>'/dashboard/studio-broadcasting')
    result=NevaehOs::Conversation.new(actor:@actor).ask(text:'create a project',request_key:SecureRandom.uuid,page_context:context)
    assert_equal 'needs_inputs',result['status']
    assert_equal ['name'],result['missing_inputs']
    assert_equal 'studio_operator',result['page_task'][:worker][:key]
    assert_equal 0,NevaehOsAction.count
  end
  def test_changed_contract_and_paused_or_deleted_specialist_block_saved_work
    result=ask
    action=NevaehOsAction.find(result['action_id'])
    @cap.update!(handler:'Changed::Worker')
    assert_raises(Gatekeeper::AuthorizationDenied) { execute(action) }
    assert_equal 'failed',action.reload.status
    @cap.update!(handler:'Messaging::Worker')
    result=ask
    action=NevaehOsAction.find(result['action_id'])
    NevaehOsAgent.find_by!(user:@actor,system_key:'mail').update!(enabled:false)
    assert_raises(Gatekeeper::AuthorizationDenied) { execute(action) }
    assert_equal 'failed',action.reload.status
    refute NevaehOs::PageWorkers.manifest(@actor,@context)[:actions].any? { |row| row[:key]=='messages.list' }
  end
  def test_reflection_has_no_execution_and_unknown_schemas_are_visible_gaps
    result=ask(mode:'reflect')
    assert_equal 'planned',result['status']
    assert_equal 0,NevaehOsAction.count
    @cap.update!(slug:'messages.send',name:'Send message')
    manifest=NevaehOs::PageWorkers.manifest(@actor,@context)
    assert_empty manifest[:actions]
    gap=manifest[:gaps].find { |entry| entry[:key]=='messages.send' }
    refute_nil gap
    assert_includes gap[:reason],'schema'
  end
  def test_inputs_are_typed_and_contracts_are_account_specific
    worker=NevaehOs::PageWorkers
    assert_equal false,worker.coerce('false',{'type'=>'boolean'})
    assert_equal({'enabled'=>false},worker.coerce('{"enabled":false}',{'type'=>'object'}))
    assert_equal [1,2],worker.coerce('[1,2]',{'type'=>'array'})
    assert_raises(ArgumentError) { worker.coerce('NaN',{'type'=>'number'}) }
    assert_raises(ArgumentError) { worker.coerce('[]',{'type'=>'object'}) }
    row=task
    request={key:row[:key],fingerprint:row[:fingerprint],inputs:{}}
    assert_raises(ArgumentError) { worker.prepare!(actor:@other,context:@context,request:request) }
    request[:inputs]={'actor_id'=>@other.id}
    assert_raises(ArgumentError) { worker.prepare!(actor:@actor,context:@context,request:request) }
    assert_equal 0,NevaehOsAction.count
  end
end
