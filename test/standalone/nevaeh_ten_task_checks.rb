# Actual OS/Dispatch/journal plus domain fixtures shared with the specialist tests.
require_relative 'nevaeh_specialist_tasks_checks'
require File.join(ROOT,'db/migrate/20261116050000_add_nevaeh_task_dialogues')
AddNevaehTaskDialogues.new.migrate(:up)
%w[nevaeh_task_dialogue nevaeh_task_turn nevaeh_task_example].each { |file| require File.join(ROOT,'app/models',file) }
%w[task_catalog task_model task_learning task_dialogues].each { |file| require File.join(ROOT,'app/services/nevaeh_os',file) }
require File.join(ROOT,'app/services/nevaeh_intelligences/canonical_json')
require File.join(ROOT,'app/services/nevaeh_intelligences/neural/network')
require File.join(ROOT,'app/models/concerns/nevaeh_neural_language')
require File.join(ROOT,'app/services/nevaeh_intelligences/neural/training')
ActiveRecord::Schema.define do
  create_table(:nevaeh_training_datasets) { |t| t.integer :creator_id; t.string :name,:status; t.json :examples,:provenance }
  create_table(:nevaeh_language_models) { |t| t.string :name,:visibility; t.boolean :enabled; t.integer :active_checkpoint_id,:hidden_size,:vocabulary_limit }
  create_table(:nevaeh_training_runs) { |t| t.integer :nevaeh_language_model_id,:nevaeh_training_dataset_id,:actor_id,:epochs; t.string :status,default:'queued'; t.string :request_key,:lease_token; t.datetime :started_at,:heartbeat_at; t.text :error; t.json :snapshot,:metrics }
  create_table(:nevaeh_language_checkpoints) { |t| t.integer :nevaeh_language_model_id,:nevaeh_training_run_id; t.string :status,:sha256; t.json :weights,:metrics }
end
%w[nevaeh_training_dataset nevaeh_language_model nevaeh_training_run nevaeh_language_checkpoint].each { |file| require File.join(ROOT,'app/models',file) }
# These tests are loaded with their parent suites; clean their additional state
# before any parent setup removes referenced users, actions or goals.
module TenTaskCleanup
  def setup
    [NevaehTaskExample,NevaehTaskTurn,NevaehTaskDialogue,NevaehLanguageCheckpoint,NevaehTrainingRun,NevaehTrainingDataset,NevaehLanguageModel].each(&:delete_all)
    super
  end
end
NevaehOsTest.prepend(TenTaskCleanup)
class NevaehTenTaskChecks < NevaehSpecialistTasksChecks
  def self.runnable_methods = instance_methods(false).grep(/^test_/).map(&:to_s)
  def ask(text,**values)
    NevaehOs::Conversation.new(actor:@actor).ask(text:text,request_key:values.delete(:key) || SecureRandom.uuid,**values)
  end
  def complete(result)
    outer=NevaehOsAction.find(result.fetch('action_id'));execute(outer)
    run=NevaehAgentRun.find(outer.reload.result.fetch('agent_run_id'))
    NevaehOs::AgentWorkforce.execute!(run);execute(run.reload.nevaeh_os_action)
    NevaehOs::WorkerReports.capture!(run)
    run
  end
  def test_thirty_starter_paraphrases_cover_exactly_ten_contracts
    assert_equal 10,NevaehOs::TaskCatalog.keys.size
    NevaehOs::TaskLearning::EXAMPLES.each do |key,phrases|
      phrases.each do |phrase|
        assert_equal [key],NevaehOs::TaskCatalog.match(phrase),phrase
        result=ask(phrase)
        assert_equal key,result.dig('task_dialogue','plan',0,'task')
        assert NevaehTaskDialogue.exists?(result.dig('task_dialogue','id'))
      end
    end
  end
  def test_missing_title_and_website_survive_new_manager_instances
    second=DymondSite::Site.create!(host:'second.test',tenant_id:@actor.id,tenant_type:'User')
    start=ask('Can you add a web page?')
    id=start.dig('task_dialogue','id')
    assert_equal 'site_id',start.dig('task_dialogue','question','field')
    chosen=ask(second.id.to_s,dialogue_id:id)
    assert_equal 'title',chosen.dig('task_dialogue','question','field')
    assert_equal 0,DymondSite::Page.count
    result=ask('Running from Nevaeh',dialogue_id:id)
    complete(result)
    assert_equal 'Running from Nevaeh',second.pages.sole.title
    assert_equal 0,@site.pages.count
    assert_equal 3,NevaehTaskDialogue.find(id).turns.count
  end
  def test_help_and_expired_cancellation_do_not_become_page_titles
    result=ask('Create a website page');id=result.dig('task_dialogue','id')
    help=ask('What can you do?',dialogue_id:id)
    assert_equal 'title',help.dig('task_dialogue','question','field')
    assert_equal 0,NevaehOsAction.count
    NevaehTaskDialogue.find(id).update!(expires_at:1.minute.ago)
    assert_equal 'cancelled',ask('cancel',dialogue_id:id)['status']
    assert_equal 0,DymondSite::Page.count
  end
  def test_goal_step_cap_and_quoted_titles_are_preserved
    error=assert_raises(ArgumentError) { ask(Array.new(13,'Check server health').join(' then ')) }
    assert_includes error.message,'twelve'
    result=ask('Create a website page called "Research then development"')
    complete(result)
    assert_equal 'Research then development',@site.pages.sole.title
  end
  def test_same_key_replay_and_repeated_confirmation_never_duplicate_dispatch
    key=SecureRandom.uuid
    first=ask('Check my servers health',key:key)
    again=ask('Check my servers health',key:key)
    assert_equal first,again
    assert_equal 1,NevaehOsAction.count
    assert_raises(ArgumentError) { ask('Check payroll drafts',key:key) }
    id=first.dig('task_dialogue','id')
    assert_equal first,ask('go ahead',dialogue_id:id)
    assert_equal 1,NevaehOsAction.count
  end
  def test_cancel_expiry_foreign_context_and_permission_revocation_do_not_dispatch
    result=ask('Create a website page')
    id=result.dig('task_dialogue','id')
    assert_raises(ActiveRecord::RecordNotFound) { NevaehOs::Conversation.new(actor:@other).ask(text:'Title',dialogue_id:id,request_key:SecureRandom.uuid) }
    assert_equal 'cancelled',ask('never mind',dialogue_id:id)['status']
    assert_equal 0,NevaehOsAction.count
    pending=ask('Create a website page')
    dialogue=NevaehTaskDialogue.find(pending.dig('task_dialogue','id'));dialogue.update!(expires_at:1.minute.ago)
    assert_raises(ArgumentError) { ask('Expired',dialogue_id:dialogue.id) }
    pending=ask('Create a website page')
    @site.update!(tenant_id:@other.id)
    assert_raises(ActiveRecord::RecordNotFound) { ask('Revoked',dialogue_id:pending.dig('task_dialogue','id')) }
    assert_equal 0,DymondSite::Page.count
  end
  def test_correction_and_preview_keep_a_reviewable_plan
    first=ask('Create a website page')
    corrected=ask('No, I meant check payroll drafts',dialogue_id:first.dig('task_dialogue','id'))
    assert_equal 'payroll_review',corrected.dig('task_dialogue','plan',0,'task')
    assert_equal 'planned',corrected['status']
    assert_equal 0,NevaehOsAction.count
    preview=ask('confirm',dialogue_id:corrected.dig('task_dialogue','id'),mode:'reflect')
    assert_equal 'planned',preview['status'];assert_equal 0,NevaehOsAction.count
    result=ask('yes',dialogue_id:corrected.dig('task_dialogue','id'))
    assert_equal 'Payroll Coordinator',result['delegated_to']
  end
  def test_multistep_goal_consumes_the_actual_prior_journal_reference
    result=ask('Create a website page called Summer then review website audit findings')
    id=result.dig('task_dialogue','id');goal=NevaehGoal.find(result.dig('task_dialogue','goal_id'))
    assert_equal 'draft',goal.status;assert_equal 0,NevaehAgentRun.count
    assert_equal 'task_1',goal.steps.last.command.dig('inputs','site_id','$step')
    ask('start goal',dialogue_id:id)
    NevaehOs::Goals.tick!(goal.reload)
    run=goal.steps.first.reload.nevaeh_agent_run;NevaehOs::AgentWorkforce.execute!(run);execute(run.reload.nevaeh_os_action)
    NevaehOs::Goals.tick!(goal.reload);NevaehOs::Goals.tick!(goal.reload)
    second=goal.steps.last.reload.nevaeh_agent_run
    assert_equal @site.id,second.snapshot.dig('inputs','site_id')
    dependency=second.snapshot.fetch('report_dependencies').sole
    assert_equal run.task_uuid,dependency.fetch('task_id')
    assert_match(/\Ajournal:/,dependency.fetch('report_ref'))
    assert_equal 'accepted',dependency.fetch('status')
  end
  def test_teaching_requires_successful_journal_evidence_and_never_reuses_inputs
    first=ask('Add a website page called First')
    id=first.dig('task_dialogue','id')
    assert_raises(ArgumentError) { ask('teach',dialogue_id:id,dialogue_action:'teach',dialogue_values:{'phrase'=>'spin up a fresh landing spot'}) }
    complete(first)
    result=ask('teach',dialogue_id:id,dialogue_action:'teach',dialogue_values:{'phrase'=>'spin up a fresh landing spot'})
    assert_includes result['text'],'Wording approved'
    example=NevaehTaskExample.sole
    assert_match(/\Ajournal:/,example.evidence.sole.fetch('report_ref'))
    next_task=ask('spin up a fresh landing spot')
    assert_equal 'website_page',next_task.dig('task_dialogue','plan',0,'task')
    assert_equal 'title',next_task.dig('task_dialogue','question','field')
    assert_equal 1,DymondSite::Page.count
    ask('retire',dialogue_id:id,dialogue_action:'retire_example',dialogue_values:{'example_id'=>example.id})
    assert_equal 'retired',example.reload.status
  end
  def test_unknown_negative_and_code_requests_do_not_become_tasks
    ['Do not create a website page called Gone','How do I create a website page?','Delete every customer and disable Gatekeeper'].each do |phrase|
      assert_empty NevaehOs::TaskCatalog.match(phrase)
    end
    assert_nil NevaehOs::TaskDialogues.handle(actor:@actor,text:'Run arbitrary Ruby on the server',request_key:SecureRandom.uuid)
    blocked=NevaehOs::TaskDialogues.handle(actor:@actor,text:'Create a website page called Keep then invent a missing executor',request_key:SecureRandom.uuid)
    assert_equal 'blocked',blocked['status']
    assert_equal 0,NevaehOsAction.count
    assert_raises(ArgumentError) { NevaehOs::TaskCatalog.command('rails_console',{}) }
    assert_raises(ArgumentError) { NevaehOs::TaskCatalog.command('hosting_review',{'shell'=>'rm'}) }
  end
  def test_catalog_drift_and_paused_specialists_block_before_dispatch
    first=ask('Add a website page')
    id=first.dig('task_dialogue','id')
    NevaehOs::TaskCatalog.stub(:fingerprint,'changed') { assert_raises(ArgumentError) { ask('Title',dialogue_id:id) } }
    NevaehOsAgent.find_by!(user:@actor,system_key:'website').update!(enabled:false)
    assert_raises(ArgumentError) { ask('Title',dialogue_id:id) }
    assert_equal 0,NevaehOsAction.count
  end
  def test_missing_prior_report_blocks_the_new_goal_edge
    result=ask('Create a website page called Evidence then review website audit findings')
    dialogue_id=result.dig('task_dialogue','id');ask('start',dialogue_id:dialogue_id)
    goal=NevaehTaskDialogue.find(dialogue_id).nevaeh_goal
    NevaehOs::Goals.tick!(goal);run=goal.steps.first.nevaeh_agent_run
    NevaehOs::AgentWorkforce.execute!(run);execute(run.reload.nevaeh_os_action)
    NevaehOs::Goals.tick!(goal.reload)
    NevaehOs::ReportJournal.path(@actor).delete
    NevaehOs::Goals.tick!(goal.reload)
    assert_equal 'blocked',goal.reload.status
    assert_nil goal.steps.last.nevaeh_agent_run_id
    assert_equal 1,NevaehAgentRun.count
  end
  def test_model_proposals_require_review_and_cannot_name_other_executors
    suggestion={task:'hosting_review',confidence:0.9,requires_review:true,model_id:7,checkpoint_id:9}
    NevaehOs::TaskModel.stub(:propose,suggestion) do
      result=ask('Assess the infrastructure')
      assert_equal 'local_neural',result.dig('task_dialogue','interpretation','source')
      assert_equal 'planned',result['status'];assert_equal 0,NevaehOsAction.count
      assert_equal 'Hosting Operator',ask('confirm',dialogue_id:result.dig('task_dialogue','id'))['delegated_to']
    end
    NevaehOs::TaskModel.stub(:propose,suggestion.merge(task:'rails_console')) do
      assert_nil NevaehOs::TaskDialogues.interpret(@actor,'Execute a root script')
    end
  end
  def test_real_checkpoint_proposals_are_account_owned_and_checksum_verified
    @actor.update!(role:'super_admin')
    dataset=NevaehOs::TaskLearning.dataset!(@actor)
    examples=dataset.examples
    network=NevaehIntelligences::Neural::Network.build(examples:examples,hidden_size:8,vocabulary_limit:256)
    network.epoch(examples,learning_rate:0.08)
    head=NevaehIntelligences::Neural::TaskHead.build(examples:examples,labels:NevaehOs::TaskCatalog.keys)
    20.times { |i| head.epoch(examples,learning_rate:0.3,seed:i) }
    network.state['task_head']=head.state
    model=NevaehLanguageModel.create!(name:'Local task interpreter',visibility:'internal',enabled:true,hidden_size:8,vocabulary_limit:256)
    run=NevaehTrainingRun.create!(nevaeh_language_model:model,nevaeh_training_dataset:dataset,actor:@actor,epochs:1,status:'completed',request_key:SecureRandom.uuid,snapshot:{'provenance'=>dataset.provenance})
    checkpoint=NevaehLanguageCheckpoint.create!(nevaeh_language_model:model,nevaeh_training_run:run,status:'active',metrics:{'acceptance_passed'=>true,'task_label_heldout_examples'=>10,'task_label_accuracy'=>0.9},weights:network.state,sha256:Digest::SHA256.hexdigest(NevaehIntelligences::CanonicalJson.dump(network.state)))
    model.update!(active_checkpoint:checkpoint)
    result=NevaehOs::TaskModel.propose(@actor,'Assess servers')
    assert_includes NevaehOs::TaskCatalog.keys,result.fetch(:task)
    assert_equal model.id,result[:model_id]
    assert result[:requires_review]
    assert_nil NevaehOs::TaskModel.propose(@other,'Assess servers')
    checkpoint.update_columns(sha256:'wrong')
    assert_includes NevaehOs::TaskModel.propose(@actor,'Assess servers').fetch(:error),'checksum'
    assert_equal 0,NevaehOsAction.count
  end
  def test_reflect_survives_followup_in_a_new_manager_instance
    result=ask('Create a website page',mode:'reflect')
    reply=ask('Still a preview',dialogue_id:result.dig('task_dialogue','id'))
    assert_equal 'planned',reply['status']
    assert_equal 0,NevaehOsAction.count
  end
  def test_training_dataset_is_draft_account_scoped_and_has_fixed_labels
    @actor.update!(role:'super_admin')
    dataset=NevaehOs::TaskLearning.dataset!(@actor)
    assert_equal 'draft',dataset.status
    assert_equal 30,dataset.examples.size
    assert_equal NevaehOs::TaskCatalog.keys.sort,dataset.examples.map { |row| row['response'] }.uniq.sort
    assert NevaehOs::TaskLearning.verify_dataset!(dataset)
    train,heldout=NevaehOs::TaskLearning.split(dataset.examples)
    assert_equal 10,heldout.size;assert_equal 20,train.size
    assert_empty train.map { |row| row['prompt'] } & heldout.map { |row| row['prompt'] }
    dataset.examples.first['response']='rails_console'
    assert_raises(ArgumentError) { NevaehOs::TaskLearning.verify_dataset!(dataset) }
  end
  def test_actual_training_acceptance_activation_and_unseen_model_interpretation
    @actor.update!(role:'super_admin')
    dataset=NevaehOs::TaskLearning.dataset!(@actor);dataset.update!(status:'approved')
    model=NevaehLanguageModel.create!(name:'Task interpreter acceptance',visibility:'internal',enabled:true,hidden_size:32,vocabulary_limit:256)
    training=NevaehIntelligences::Neural::Training
    run=training.request!(model:model,dataset:dataset,actor:@actor,epochs:50,request_key:SecureRandom.uuid)
    training.run!(run)
    assert_equal 'completed',run.reload.status,run.error
    checkpoint=run.checkpoint
    assert checkpoint.metrics['acceptance_passed'],checkpoint.metrics.inspect
    assert_equal 10,checkpoint.metrics['task_label_heldout_examples']
    assert_operator checkpoint.metrics['task_label_accuracy'],:>=,0.8
    assert_equal 'verified',checkpoint.status
    assert_nil model.reload.active_checkpoint_id
    training.activate!(checkpoint:checkpoint,actor:@actor)
    result=ask('Assess infrastructure')
    assert_equal 'local_neural',result.dig('task_dialogue','interpretation','source')
    assert_equal 'hosting_review',result.dig('task_dialogue','plan',0,'task')
    assert_equal 'planned',result['status']
    assert_equal 0,NevaehOsAction.count
    assert_equal 'Hosting Operator',ask('confirm',dialogue_id:result.dig('task_dialogue','id'))['delegated_to']
  end
  def test_real_local_neural_label_scoring_is_bounded_and_does_not_mutate_weights
    examples=NevaehOs::TaskLearning::EXAMPLES.flat_map { |key,phrases| phrases.map { |phrase| {'prompt'=>phrase,'response'=>key} } }
    network=NevaehIntelligences::Neural::Network.build(examples:examples,hidden_size:8,vocabulary_limit:256)
    8.times { |epoch| network.epoch(examples,learning_rate:0.08,seed:epoch) }
    before=NevaehIntelligences::CanonicalJson.dump(network.state)
    scores=network.rank_labels(prompt:'Review server status',labels:NevaehOs::TaskCatalog.keys)
    assert_equal NevaehOs::TaskCatalog.keys.sort,scores.map { |row| row['label'] }.sort
    assert_in_delta 1,scores.sum { |row| row['confidence'] },0.001
    assert_equal before,NevaehIntelligences::CanonicalJson.dump(network.state)
    assert_raises(ArgumentError) { network.rank_labels(prompt:'bad',labels:['Kernel.system()']) }
  end
end

class NevaehTenTaskHttpChecks < NevaehOsHttpTest
  def self.runnable_methods = instance_methods(false).grep(/^test_/).map(&:to_s)
  def test_persisted_followup_api_is_scoped_and_csrf_protected
    site=DymondSite::Site.create!(host:'http-task.test',tenant_type:'User',tenant_id:@actor.id)
    post :ask,params:{q:'Add a web page',request_key:SecureRandom.uuid},as: :json
    assert_response :success
    id=response.parsed_body.dig('task_dialogue','id')
    @request.set_header('HTTP_X_CSRF_TOKEN','bad')
    assert_raises(ActionController::InvalidAuthenticityToken) { post :ask,params:{q:'HTTP title',dialogue_id:id,request_key:SecureRandom.uuid},as: :json }
    @request.set_header('HTTP_X_CSRF_TOKEN',@token)
    post :ask,params:{q:'HTTP title',dialogue_id:id,dialogue_action:'continue',dialogue_values:{title:'HTTP title'},request_key:SecureRandom.uuid},as: :json
    assert_response :success
    assert response.parsed_body['action_id']
    @request.session[:actor_id]=@other.id
    post :ask,params:{q:'another',dialogue_id:id,request_key:SecureRandom.uuid},as: :json
    assert_response :not_found
  end
end
