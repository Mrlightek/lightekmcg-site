# frozen_string_literal: true
require_relative 'nevaeh_os_test'
require File.join(ROOT, 'db/migrate/20261114230000_create_nevaeh_manual_learning')
CreateNevaehManualLearning.new.migrate(:up)
%w[services/nevaeh_intelligences/canonical_json services/nevaeh_os/language_contract
 models/nevaeh_manual_build models/nevaeh_language_binding services/nevaeh_os/language].each { |file| require File.join(ROOT, 'app', file) }

class NevaehManualConversationTest < Minitest::Test
  def setup
    @actor = User.create!(role: 'super_admin')
    doc = NevaehIntelligences::SoftwareLibrary.new.documents.find { |entry| entry[:path] == 'docs/nevaeh/tutorials/agents.md' }
    @binding = NevaehLanguageBinding.create!(creator: @actor, name: 'List my workforce', patterns: ['show my workforce'], slots: {},
      command_template: {'kind'=>'resource','resource'=>'agents','operation'=>'read','attributes'=>{}},
      source_refs: [{'path'=>doc[:path],'sha256'=>doc[:sha256],'title'=>doc[:title]}])
    NevaehOs::Language.activate!(binding: @binding, actor: @actor)
  end
  def teardown
    NevaehLanguageBinding.delete_all
  end
  def ask(text, key: 'manual-task-request', mode: 'operate')
    NevaehOs::Conversation.new(actor: @actor).ask(text: text, request_key: key, mode: mode)
  end
  def execute(id) = NevaehOs::Worker.perform('execute', {'action_id'=>id})
  def test_conversation_phrase_reaches_real_gatekeeper_dispatch_and_resource_receipt
    NevaehOsAgent.create!(user: @actor, name: 'Example worker', role: 'Example')
    result = ask('show my workforce')
    action = NevaehOsAction.find(result['action_id'])
    assert_equal @binding.id, action.command['language_binding']['id']
    assert_equal 'List my workforce', result['language_binding']
    assert_equal 'docs/nevaeh/tutorials/agents.md', result['sources'].first['path']
    assert DymondDispatch::WorkItem.exists?(subject_type:'NevaehOsAction',subject_id:action.id)
    receipt = execute(action.id)
    assert_includes receipt['records'].map { |row| row['name'] }, 'Example worker'
    assert_equal 'completed', action.reload.status
    assert_equal action.id, ask('show my workforce')['action_id']
  end
  def test_recurring_conversation_creates_a_real_agent_worker_with_bound_command
    result = ask('every 60 minutes, show my workforce', key: 'manual-recurring-task')
    receipt = execute(result['action_id'])
    worker = NevaehAgentWorker.find(receipt['agent_worker_id'])
    assert_equal 60, worker.interval_minutes
    assert_equal @binding.id, worker.command['language_binding']['id']
    run = NevaehOs::AgentWorkforce.request!(worker: worker, actor: @actor, key: 'manual-recurring-run')
    NevaehOs::AgentWorkforce.execute!(run)
    assert run.reload.nevaeh_os_action_id
    execute(run.nevaeh_os_action_id)
    assert_equal 'completed', run.nevaeh_os_action.reload.status
  end
  def test_paused_binding_blocks_an_already_queued_action
    result = ask('show my workforce', key: 'manual-paused-binding')
    @binding.update!(status: 'paused')
    assert_raises(Gatekeeper::AuthorizationDenied) { execute(result['action_id']) }
    assert_equal 'failed', NevaehOsAction.find(result['action_id']).status
  end
  def test_reflection_and_ambiguous_phrases_do_not_dispatch
    count = NevaehOsAction.count
    assert_equal 'planned', ask('show my workforce', key: 'manual-plan-only', mode: 'reflect')['status']
    assert_equal count, NevaehOsAction.count
    other = NevaehLanguageBinding.create!(creator: @actor, name: 'Different task', patterns: @binding.patterns, slots: {},
      command_template: {'kind'=>'ticket','text'=>'A different action'}, source_refs: @binding.source_refs)
    NevaehOs::Language.activate!(binding: other, actor: @actor)
    assert_equal 'needs_clarification', ask('show my workforce', key: 'manual-ambiguous-task')['status']
    assert_equal count, NevaehOsAction.count
  end
  def test_agent_restrictions_and_non_admin_accounts_cannot_bypass_authority
    agent = NevaehOs::Agents.resolve!('nevaeh', @actor)
    agent.update!(allowed_capabilities: ['studio.*'])
    assert_raises(ArgumentError) { ask('show my workforce', key: 'manual-restricted-task') }
    client = User.create!(role: 'client')
    assert_nil NevaehOs::Language.resolve('show my workforce', actor: client)
    command = @binding.command_template.merge('language_binding'=>{'id'=>@binding.id,'fingerprint'=>@binding.fingerprint})
    assert_raises(ArgumentError) { NevaehOs::Dispatch.submit!(actor: client, command: command, request_key: 'manual-client-task') }
  end
  def test_missing_inputs_are_completed_in_chat_and_scheduling_is_preserved
    person = NevaehOsAgent.create!(user: @actor, name: 'Chosen member', role: 'Example')
    row = NevaehLanguageBinding.create!(creator: @actor, name: 'Inspect workforce member', patterns: ['show workforce member {id}'], slots: {'id'=>'integer'},
      command_template: {'kind'=>'resource','resource'=>'agents','operation'=>'read','attributes'=>{},'id'=>'{id}'}, source_refs: @binding.source_refs)
    NevaehOs::Language.activate!(binding: row, actor: @actor)
    result = ask('could you please show workforce member', key: 'manual-missing-input')
    assert_equal 'needs_clarification', result['status']
    assert_equal row.id, result['language_request']['binding_id']
    completed = NevaehOs::Conversation.new(actor: @actor).ask(text:'show workforce member',request_key:'manual-input-completed',binding_id:row.id,binding_fingerprint:row.fingerprint,language_slots:{'id'=>person.id.to_s})
    receipt = execute(completed['action_id'])
    assert_equal 'Chosen member', receipt['records'].first['name']
    recurring = ask('every 60 minutes, show workforce member', key:'manual-missing-schedule')
    assert_equal 60, recurring['language_request']['interval_minutes']
    assert_raises(ArgumentError) { NevaehOs::Language.bind!(binding_id:row.id,fingerprint:row.fingerprint,values:{'id'=>person.id.to_s,'role'=>'super_admin'},actor:@actor) }
    assert_raises(ArgumentError) { NevaehOs::Language.bind!(binding_id:row.id,fingerprint:row.fingerprint,values:{'id'=>'not a number'},actor:@actor) }
    other = User.create!(role:'client'); foreign = NevaehOsAgent.create!(user:other,name:'Foreign',role:'Other')
    assert_raises(ActiveRecord::RecordNotFound) do
      NevaehOs::Conversation.new(actor:@actor).ask(text:'show workforce member',request_key:'manual-foreign-input',binding_id:row.id,binding_fingerprint:row.fingerprint,language_slots:{'id'=>foreign.id.to_s})
    end
  end
  def test_a_binding_stamp_cannot_authorize_a_different_saved_command
    result = ask('show my workforce', key:'manual-forged-stamp')
    command = NevaehOsAction.find(result['action_id']).command.merge('resource'=>'sources')
    assert_raises(ArgumentError) { NevaehOs::Executor.authorize_command!(actor:@actor,command:command) }
  end
end
