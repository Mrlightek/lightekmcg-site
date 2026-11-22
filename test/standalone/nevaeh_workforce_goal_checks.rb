require_relative 'nevaeh_os_test'
require File.join(ROOT, 'app/services/nevaeh_os/website_marketing')
class NevaehWorkforceGoalChecks < NevaehOsTest
  def self.runnable_methods = instance_methods(false).grep(/^test_/).map(&:to_s)
  def teardown
    NevaehGoalStep.delete_all;NevaehGoal.delete_all
  end
  def values
    {'title'=>'Create and classify a worker','steps'=>[
      {'key'=>'create','label'=>'Create role','agent'=>'nevaeh','command'=>'/create agents {"name":"Auditor","role":"Review"}','expectations'=>[{'path'=>'result.record.name','equals'=>'Auditor'}]},
      {'key'=>'classify','label'=>'Use actual created ID','agent'=>'nevaeh','command'=>{'kind'=>'resource','operation'=>'update','resource'=>'agents','id'=>{'$step'=>'create','path'=>'result.record.id'},'attributes'=>{'role'=>'Acceptance checks'}},'expectations'=>[{'path'=>'result.record.role','equals'=>'Acceptance checks'}]}
    ]}
  end
  def goal(data=values,key:SecureRandom.uuid) = NevaehOs::Goals.create!(actor:@actor,values:data,request_key:key)
  def complete_current(plan)
    NevaehOs::Goals.tick!(plan.reload)
    step=plan.steps.where(status:'running').first
    assert step, plan.reload.error
    run=step.nevaeh_agent_run
    NevaehOs::AgentWorkforce.execute!(run)
    execute(run.reload.nevaeh_os_action)
    NevaehOs::Goals.tick!(plan.reload)
  end
  def test_website_goal_dispatches_the_marketing_sme_and_records_the_publication_receipt
    assert_marketing_goal_dispatch(
      { 'kind' => 'website_marketing', 'operation' => 'compose', 'site_id' => 91, 'values' => { 'published' => true } },
      { 'published' => true, 'page_id' => 12 })
  end

  def test_journal_goal_dispatches_the_marketing_sme_and_records_the_publication_receipt
    command = NevaehOs::Command.parse('/website journal_write 91 {"entry_id":12,"revision":0,"status":"published"}')
    assert_equal 'journal_write', command.fetch('operation')
    assert_marketing_goal_dispatch(command, { 'published' => true, 'entry_id' => 12, 'article_status' => 'published' })
  end

  def assert_marketing_goal_dispatch(command, result)
    operations = NevaehOs::WebsiteMarketing
    bind = ->(_actor, input) { input.merge('delegation_id' => 'fixture-grant') }
    execute_site = lambda do |actor:, command:, action_id:|
      assert_equal @actor.id, actor.id
      assert_equal 'fixture-grant', command.fetch('delegation_id')
      assert_operator action_id, :>, 0
      result.merge('status' => 'completed')
    end

    NevaehOs::Guide.stub(:allowed?, ->(level, actor) { level == 'growth' && actor.id == @actor.id }) do
      operations.stub(:bind, bind) do
        operations.stub(:authorize!, true) do
          operations.stub(:perform!, execute_site) do
            plan = goal({ 'title' => 'Execute a delegated publication', 'steps' => [{
              'key' => 'publish', 'agent' => 'marketing_strategy', 'command' => command,
              'expectations' => [{ 'path' => 'result.published', 'equals' => true }]
            }] })
            NevaehOs::Goals.control!(goal: plan, actor: @actor, operation: 'start')
            complete_current(plan)
            assert_equal 'completed', plan.reload.status
            assert_equal 'marketing_strategy', plan.steps.first.nevaeh_os_agent.system_key
          end
        end
      end
    end
  end

  def test_default_roles_are_defined_owned_and_do_not_resurrect_after_deletion
    NevaehOs::Workforce.install!(@actor)
    assert_equal NevaehOs::Workforce::ROLES.size, NevaehOsAgent.where(user: @actor).count
    sage=NevaehOsAgent.find_by!(user:@actor,system_key:'sage')
    assert_includes sage.instructions,'growth'
    NevaehOs::Workforce.remove_agent!(@actor,sage.id)
    NevaehOs::Workforce.install!(@actor)
    assert_equal NevaehOs::Workforce::ROLES.size, NevaehOsAgent.where(user: @actor).count
    assert sage.reload.deleted_at
    assert_raises(ArgumentError) { NevaehOs::Agents.resolve!('sage',@actor) }
    assert_raises(ActiveRecord::RecordNotFound) { NevaehOs::Workforce.remove_agent!(@other,sage.id) }
    assert_raises(ArgumentError) { NevaehOs::Workforce.remove_agent!(@actor,NevaehOsAgent.find_by!(user:@actor,system_key:'nevaeh').id) }
  end
  def test_directory_exposes_registered_examples_for_connected_actions
    rows=NevaehOs::Workforce.rows(@actor)
    capabilities=rows.flat_map { |row| row[:capabilities] }
    refute_empty capabilities
    catalog=NevaehOs::Guide.catalog(actor:@actor).index_by { |entry| entry[:key] }
    capabilities.each do |capability|
      assert_equal catalog.fetch(capability[:key])[:example],capability[:example]
    end
  end
  def test_deletion_stops_future_runs_and_keeps_actual_execution_history
    agent=NevaehOs::Agents.resolve!('sage',@actor)
    result=NevaehOs::AgentWorkforce.create!(actor:@actor,command:{'agent_ref'=>'sage','command'=>command('/create agents {"name":"Job child"}')},key:'delegated-task')
    run=NevaehAgentRun.find(result['agent_run_id']);worker=run.nevaeh_agent_worker
    NevaehOs::Workforce.remove_agent!(@actor,agent.id)
    assert NevaehAgentWorker.exists?(worker.id);assert NevaehAgentRun.exists?(run.id)
    assert_equal 'blocked',run.reload.status
    NevaehOs::AgentWorkforce.execute!(run)
    assert_nil run.reload.nevaeh_os_action_id
    assert_empty NevaehOs::Resources.perform!(actor:@actor,command:{'resource'=>'agent_workers','operation'=>'read'})['records']
  end
  def test_goal_waits_for_dispatch_completion_then_passes_real_output_to_next_specialist
    plan=goal
    assert_equal 'draft',plan.status
    NevaehOs::Goals.control!(goal:plan,actor:@actor,operation:'start')
    NevaehOs::Goals.tick!(plan)
    assert_equal ['running','waiting'],plan.steps.map(&:status)
    NevaehOs::Goals.tick!(plan.reload)
    assert_equal 1,NevaehAgentRun.count
    complete_current(plan)
    assert_equal ['completed','waiting'],plan.steps.reload.map(&:status)
    complete_current(plan)
    assert_equal 'completed',plan.reload.status
    auditor=NevaehOsAgent.find_by!(user:@actor,name:'Auditor')
    assert_equal 'Acceptance checks',auditor.role
    assert_equal auditor.id,plan.steps.last.evidence.dig('result','record','id')
    2.times { NevaehOs::Goals.tick!(plan.reload) }
    assert_equal 2,NevaehAgentRun.count
  end
  def test_replay_pause_cancel_and_foreign_goal_controls_do_not_duplicate_work
    key=SecureRandom.uuid;plan=goal(key:key)
    assert_equal plan.id,goal(key:key).id
    assert_raises(ArgumentError) { goal(values.merge('title'=>'Different'),key:key) }
    assert_raises(ActiveRecord::RecordNotFound) { NevaehOs::Goals.control!(goal:plan,actor:@other,operation:'start') }
    NevaehOs::Goals.control!(goal:plan,actor:@actor,operation:'start')
    NevaehOs::Goals.control!(goal:plan,actor:@actor,operation:'pause')
    NevaehOs::Goals.tick!(plan);assert_equal 0,NevaehAgentRun.count
    NevaehOs::Goals.control!(goal:plan,actor:@actor,operation:'resume')
    NevaehOs::Goals.tick!(plan)
    NevaehOs::Goals.control!(goal:plan,actor:@actor,operation:'cancel')
    NevaehOs::Goals.tick!(plan)
    assert_equal 'cancelled',plan.reload.status
    assert_equal 1,NevaehAgentRun.count
    assert_equal 'blocked',NevaehAgentRun.first.status
  end
  def test_missing_outputs_failed_verification_and_permission_changes_block_progress
    bad=values;bad['steps'][0]['expectations'][0]['equals']='Wrong'
    plan=goal(bad);NevaehOs::Goals.control!(goal:plan,actor:@actor,operation:'start');complete_current(plan)
    assert_equal 'blocked',plan.reload.status
    assert_equal 'waiting',plan.steps.last.status
    assert_equal 'blocked',NevaehOs::Goals.verdict({status:'completed',result:{status:'failed'}},{'kind'=>'build'},[]).first
    assert_equal 'blocked',NevaehOs::Goals.verdict({status:'completed',downstream:{status:'completed',metrics:{acceptance_passed:false}}},{'kind'=>'train'},[]).first
    assert_equal 'completed',NevaehOs::Goals.verdict({status:'completed',result:{flag:false}},{'kind'=>'resource'},[{'path'=>'result.flag','equals'=>false}]).first
    fresh=goal;NevaehOs::Goals.control!(goal:fresh,actor:@actor,operation:'start')
    fresh.steps.first.nevaeh_os_agent.update!(enabled:false)
    NevaehOs::Goals.tick!(fresh)
    assert_equal 'blocked',fresh.reload.status
  end
  def test_forward_references_arbitrary_commands_and_foreign_roles_are_rejected
    bad=values;bad['steps'][0]['command']={'kind'=>'resource','operation'=>'update','resource'=>'agents','id'=>{'$step'=>'classify','path'=>'result.record.id'}}
    assert_raises(ArgumentError) { goal(bad) }
    assert_raises(ArgumentError) { goal(values.merge('steps'=>[{'agent'=>'nevaeh','command'=>'hello, invent a task'}])) }
    foreign=NevaehOs::Agents.resolve!('sage',@other)
    bad=values;bad['steps'][0]['agent']=foreign.id.to_s
    assert_raises(ActiveRecord::RecordNotFound) { goal(bad) }
  end
  def test_goal_and_role_lifecycle_cannot_be_bypassed_by_raw_model_writes
    plan=goal
    assert_raises(ArgumentError) { NevaehOs::RailsConsole.execute("NevaehGoal.find(#{plan.id}).update!(status: \"completed\")",@actor) }
    agent=plan.steps.first.nevaeh_os_agent
    assert_raises(ArgumentError) { NevaehOs::RailsConsole.execute("NevaehOsAgent.find(#{agent.id}).destroy!",@actor) }
    assert_equal 'draft',plan.reload.status
    assert NevaehOsAgent.exists?(agent.id)
  end
  def test_goal_command_preview_is_read_only_and_improvement_tasks_are_registered
    result=NevaehOs::Conversation.new(actor:@actor).ask(text:'/goal '+values.to_json,request_key:SecureRandom.uuid,mode:'decide')
    assert_equal 'planned',result['status'];assert_equal 0,NevaehGoal.count
    assert_equal 'improve',command('/improve language_check')['kind']
    assert_equal 'goal_control',command('/goal start 3')['kind']
    assert_equal 'goals',command('/goal list')['kind']
  end
end
class NevaehWorkforceHttpChecks < NevaehOsHttpTest
  def self.runnable_methods = instance_methods(false).grep(/^test_/).map(&:to_s)
  def teardown
    NevaehGoalStep.delete_all;NevaehGoal.delete_all
  end
  def test_workforce_endpoint_explains_default_roles_and_keeps_other_accounts_out
    NevaehOs::Agents.resolve!('sage',@other)
    get :workforce,format: :json
    assert_response :success
    rows=JSON.parse(response.body)['roles']
    assert_equal NevaehOs::Workforce::ROLES.size, rows.size
    marketing = rows.find { |row| row['system_key'] == 'marketing_strategy' }
    assert_equal 'Marketing SME', marketing.fetch('name')
    assert_includes marketing.fetch('allowed_capabilities'), 'growth.backlink.draft'
    assert_includes marketing.fetch('allowed_capabilities'), 'website.marketing.*'
    assert rows.all? { |row| row['purpose'].present? && row['department'].present? }
    refute rows.any? { |row| row['id']==NevaehOsAgent.find_by!(user:@other,system_key:'sage').id }
  end
  def test_page_context_is_immediate_sanitized_and_does_not_read_form_values
    post :page_context,params:{page_context:{path:'/dashboard/studio-broadcasting',search:'?site_id=12&token=private-page-context-7b2b2c',title:'My Studio',password:'do-not-read'}},format: :json
    assert_response :success
    result=JSON.parse(response.body)
    assert_equal 'Studio & production',result.dig('page','area')
    assert_equal '12',result.dig('page','site_id')
    assert_equal %w[area path site_id title],result.fetch('page').keys.sort
    refute_includes response.body,'private-page-context-7b2b2c';refute_includes response.body,'do-not-read'
    refute result.fetch('page').key?('password')
    assert result['specialists'].any? { |row| row['key']=='producer' }
  end
  def test_goal_create_is_csrf_protected_and_creates_a_reviewable_draft
    @request.set_header('HTTP_X_CSRF_TOKEN','bad')
    assert_raises(ActionController::InvalidAuthenticityToken) { post :goals,params:{request_key:'goal-http-123',goal:{title:'Do work',steps:[]}},format: :json }
    @request.set_header('HTTP_X_CSRF_TOKEN',@token)
    post :goals,params:{request_key:'goal-http-123',goal:{title:'Prepare role',steps:[{agent:'nevaeh',command:'/create agents {"name":"Test specialist"}'}]}},format: :json
    assert_response :success
    assert_equal 'draft',JSON.parse(response.body)['status']
    assert_equal @actor.id,NevaehGoal.last.user_id
    assert_equal 0,NevaehGoal.last.steps.where.not(nevaeh_agent_run_id:nil).count
  end
end
class NevaehPageContextChecks < NevaehOsTest
  def self.runnable_methods = instance_methods(false).grep(/^test_/).map(&:to_s)
  def test_conversational_capability_question_precedes_unrelated_document_search
    conversation=NevaehOs::Conversation.new(actor:@actor)
    ['Hello, tell me what you can help me do.','What options do you have?','What can you do?','How can you help me?','help'].each do |phrase|
      result=conversation.ask(text:phrase,request_key:SecureRandom.uuid,page_context:{path:'/dashboard/nevaeh',title:'Nevaeh'})
      assert_equal 'ready',result['status'],phrase
      assert_includes result['text'],'delegate supported tasks'
      refute_includes result['text'],"Here's what I found in the documentation"
      refute_includes result['text'],'Quran'
      assert_equal '/dashboard/nevaeh/guide',result['guide_url']
    end
    assert_equal 0,NevaehOsAction.count
    refute NevaehOs::PageContext.overview_question?('What can you do here?')
    refute NevaehOs::PageContext.overview_question?('Find documentation about what options do you have')
  end
  def test_context_help_uses_current_area_and_reading_help_never_executes
    result=NevaehOs::Conversation.new(actor:@actor).ask(text:'What can you do here?',request_key:SecureRandom.uuid,page_context:{path:'/dashboard/servers',search:'?site_id=42&secret=x',title:'Servers'})
    assert_equal 'grounded',result[:status]
    assert_equal 'Servers, applications & domains',result.dig(:page,'area')
    assert_equal 0,NevaehOsAction.count
    assert_raises(ArgumentError) { NevaehOs::PageContext.normalize({'path'=>'https://evil.example/dashboard/servers'}) }
    assert_raises(ArgumentError) { NevaehOs::PageContext.normalize({'path'=>'//evil.example/dashboard/servers'}) }
  end
  def test_client_page_assistance_excludes_internal_document_sources
    result=NevaehOs::PageContext.help(@other,{'path'=>'/dashboard/payouts','title'=>'Payouts'})
    assert_equal 'Finance & accounting',result.dig(:page,'area')
    assert_empty result[:sources]
    assert_equal '/dashboard/nevaeh/guide?topic=commands',result[:guide_url]
  end
end
