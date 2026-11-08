# frozen_string_literal: true
require_relative 'nevaeh_control_center_render_test'
require 'tmpdir'
require 'faker'
%w[services/nevaeh_intelligences/software_library services/nevaeh_intelligences/contextual_help
 models/nevaeh_construction models/nevaeh_construction_release
 services/nevaeh_intelligences/factory/contract services/nevaeh_intelligences/factory/runtime services/nevaeh_intelligences/factory/compiler services/nevaeh_intelligences/factory/execution services/nevaeh_intelligences/factory_worker
 services/nevaeh_intelligences/neural/network services/nevaeh_intelligences/neural/corpus_factory
 models/nevaeh_training_dataset models/nevaeh_training_run models/nevaeh_language_checkpoint
 models/nevaeh_conversation models/nevaeh_conversation_turn
 services/nevaeh_intelligences/neural/training jobs/nevaeh_intelligences/neural/training_job jobs/nevaeh_intelligences/factory_sweep_job].each { |file| require File.join(ROOT, 'app', "#{file}.rb") }
ActiveRecord::Base.connection.add_column(:nevaeh_capabilities, :metadata, :json, default: {}) unless NevaehCapability.column_names.include?('metadata')
ActiveRecord::Base.connection.add_column(:nevaeh_capabilities, :description, :text) unless NevaehCapability.column_names.include?('description')
NevaehCapability.reset_column_information

class NevaehDigitalFactoryTest < Minitest::Test
  def setup
    Rails.env = 'test'; ENV['NEVAEH_BACKLOG_ENABLED'] = '1'
    @actor = User.create!(role: 'super_admin')
  end
  def teardown
    NevaehConstruction.update_all(active_release_id: nil)
    NevaehLanguageModel.update_all(active_checkpoint_id: nil)
    [NevaehConversationTurn, NevaehConversation, NevaehLanguageCheckpoint, NevaehTrainingRun, NevaehTrainingDataset, NevaehWritingProfile, NevaehLanguageModel, NevaehConstructionRelease, NevaehConstruction].each(&:delete_all)
  end
  def definition
    {'input_schema'=>{'name'=>'string'},'steps'=>[{'op'=>'normalize','field'=>'name','mode'=>'strip'},{'op'=>'template','field'=>'greeting','text'=>'Welcome, {name}.'},{'op'=>'require','fields'=>['greeting']}]}
  end
  def samples
    [{'inputs'=>{'name'=>' Marlon '},'expected'=>{'name'=>'Marlon','greeting'=>'Welcome, Marlon.'}}]
  end
  def construction
    NevaehConstruction.create!(creator:@actor,name:'Greeting factory',key:"greeting_#{SecureRandom.hex(4)}",definition:definition,sample_tests:samples)
  end
  def examples
    (1..10).map { |index| {'prompt'=>"hello person #{index}",'response'=>'hello welcome to the studio'} }
  end
  def approved_dataset
    NevaehTrainingDataset.create!(creator:@actor,name:'Greetings',examples:examples,status:'approved')
  end
  def trained
    model=NevaehLanguageModel.create!(name:'Native conversation',hidden_size:8,vocabulary_limit:64)
    run=NevaehIntelligences::Neural::Training.request!(model:model,dataset:approved_dataset,actor:@actor,epochs:12,request_key:"request-#{SecureRandom.hex(5)}")
    NevaehIntelligences::Neural::Training.run!(run)
    [model,run.reload,run.checkpoint]
  end
  def test_construction_compiles_verifies_and_registers_real_connection
    record=construction
    release=NevaehIntelligences::Factory::Compiler.build!(construction:record,actor:@actor)
    assert_equal 'verified',release.status
    assert_equal %w[service.rb service_test.rb verifier.rb worker.rb],release.artifacts.keys.sort
    refute_includes release.artifacts.values.join,'NotImplementedError'
    service=NevaehIntelligences::Factory::Compiler.load!(release)::Service
    assert_equal({'name'=>'Marlon','greeting'=>'Welcome, Marlon.'},service.call(inputs:{'name'=>' Marlon '}))
    NevaehIntelligences::Factory::Compiler.activate!(release:release,actor:@actor)
    cap=NevaehCapability.find_by!(slug:record.capability_key)
    assert cap.enabled?
    assert_equal 'NevaehIntelligences::FactoryWorker',cap.handler
    assert_equal release.id,cap.metadata['release_id'] if cap.respond_to?(:metadata)
    assert_equal release.id,record.reload.active_release_id
    assert_equal 'published',NevaehIntelligence.find_by!(intent_key:record.capability_key).status
  end
  def test_constructed_worker_executes_through_real_ticket_gate_and_acceptance
    record=construction
    release=NevaehIntelligences::Factory::Compiler.build!(construction:record,actor:@actor)
    NevaehIntelligences::Factory::Compiler.activate!(release:release,actor:@actor)
    ticket=Marlon::Ticket.create!(title:'Construct greeting',category:Marlon::TicketCategories.ids.first,priority:'medium',urgency:5,status:'open',submitted_by:@actor)
    steps=[{'id'=>'greeting','action'=>'factory.construct.execute','inputs'=>{'release_id'=>release.id,'data'=>{'name'=>' Marlon '}},'depends_on'=>[]}]
    NevaehIntelligences::StructuredTicket.attach!(ticket:ticket,actor:@actor,sections:steps,automatic:true)
    NevaehIntelligences::StructuredTicket.registered!
    NevaehIntelligences::StructuredTicket.plan!(ticket:ticket)
    assert ticket.reload.extra_fields.dig('nevaeh_backlog','knowledge_article_ids').any?
    fields=ticket.extra_fields
    fields['nevaeh']={'actor_id'=>@actor.id,'reservation_id'=>'factory-proof','work_order_sha256'=>NevaehIntelligences::TicketApproval.fingerprint(fields['nevaeh_work_order']),'intent_key'=>'ticket.structured.execute','execution_status'=>'dispatch_reserved'}
    ticket.update!(extra_fields:fields)
    assert_raises(NevaehIntelligences::WorkOrder::Invalid) { NevaehIntelligences::Factory::Execution.perform!(release:release,inputs:{'name'=>'Other'},ticket:ticket,actor:@actor) }
    assert_raises(Gatekeeper::AuthorizationDenied) { Gatekeeper.authorize_capability!(capability:record.capability_key) }
    result=NevaehIntelligences::StructuredExecution.execute!(ticket:ticket,reservation:'factory-proof')
    assert result['verified']
    assert_equal 'resolved',ticket.reload.status
    assert_equal 'Welcome, Marlon.',ticket.extra_fields.dig('nevaeh_structured','steps','greeting','output','result','greeting')
    assert_equal 'verified',ticket.extra_fields.dig('nevaeh','execution_status')
  end
  def test_failed_expected_sample_cannot_activate
    record=construction
    record.update!(sample_tests:[{'inputs'=>{'name'=>'Marlon'},'expected'=>{'greeting'=>'wrong'}}])
    release=NevaehIntelligences::Factory::Compiler.build!(construction:record,actor:@actor)
    assert_equal 'failed',release.status
    assert_raises(ArgumentError) { NevaehIntelligences::Factory::Compiler.activate!(release:release,actor:@actor) }
    refute NevaehCapability.exists?(slug:record.capability_key)
  end
  def test_source_interpolation_cannot_become_ruby_execution
    record=construction
    literal='#{raise "must never execute"}'
    record.update!(definition:{'input_schema'=>{'name'=>'string'},'steps'=>[{'op'=>'defaults','values'=>{'literal'=>literal}}]},sample_tests:[{'inputs'=>{'name'=>'A'},'expected'=>{'name'=>'A','literal'=>literal}}])
    release=NevaehIntelligences::Factory::Compiler.build!(construction:record,actor:@actor)
    assert_equal 'verified',release.status
    assert_equal literal,NevaehIntelligences::Factory::Compiler.load!(release)::Service.call(inputs:{'name'=>'A'})['literal']
  end
  def test_releases_are_immutable_and_json_key_order_is_stable
    record=construction
    release=NevaehIntelligences::Factory::Compiler.build!(construction:record,actor:@actor)
    refute release.update(definition:{})
    assert_raises(ArgumentError) { NevaehIntelligences::Factory::Runtime.call(definition:definition,inputs:{'name'=>123}) }
    assert_equal NevaehIntelligences::CanonicalJSON.dump({'b'=>1,'a'=>2}),NevaehIntelligences::CanonicalJSON.dump({'a'=>2,'b'=>1})
    release.reload
    assert_equal 'Welcome, A.',NevaehIntelligences::Factory::Compiler.load!(release)::Service.call(inputs:{'name'=>'A'})['greeting']
  end
  def test_non_admin_cannot_build_and_unbound_ticket_cannot_run_factory
    employee=User.create!(role:'employee')
    assert_raises(ArgumentError) { NevaehIntelligences::Factory::Compiler.build!(construction:construction,actor:employee) }
    assert_raises(NevaehIntelligences::WorkOrder::Invalid) { NevaehIntelligences::FactoryWorker.perform('destroy',{}) }
  end
  def test_editorial_notes_change_output_and_report_unsupported_notes
    profile={'format'=>'caption','provider'=>'rules','templates'=>["Let's talk about {topic}."],'examples'=>[],'instructions'=>"Tone: formal\nMax words: 20\nOpening: Welcome to {topic}\nClosing: {call_to_action}\nMake it magic"}
    result=NevaehIntelligences::WritingEngine.generate(format:'caption',context:{'topic'=>'Studio','call_to_action'=>'Join us.'},profile:profile)
    assert_includes result['text'],'Welcome to Studio'
    assert_includes result['text'],'let us talk about Studio'
    assert_includes result['text'],'Join us.'
    assert_equal 'formal',result['editorial'][:applied]['tone']
    assert_equal ['Make it magic'],result['editorial'][:unsupported]
  end
  def test_software_library_search_blocks_symlinks_and_excluded_trees
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root,'docs','nevaeh'));FileUtils.mkdir_p(File.join(root,'storage'))
      File.write(File.join(root,'docs','nevaeh','guide.md'),"# Factory guide\nBuild the verified service.")
      File.write(File.join(root,'storage','secret.md'),'never expose')
      File.symlink('/etc/passwd',File.join(root,'docs','leak.md'))
      library=NevaehIntelligences::SoftwareLibrary.new(root:root)
      assert_equal 1,library.documents.length
      assert_equal 'Factory guide',library.search(query:'verified').first[:title]
      assert_raises(NevaehIntelligences::SoftwareLibrary::Missing) { library.find('../etc/passwd') }
      assert_raises(NevaehIntelligences::SoftwareLibrary::Missing) { library.find('storage/secret.md') }
    end
  end
  def test_document_renderer_escapes_source_html
    helper=Object.new.extend(ActionView::Helpers::TagHelper).extend(ActionView::Helpers::OutputSafetyHelper).extend(NevaehHelpHelper)
    html=helper.nevaeh_document_html("# Manual\n<script>alert('x')</script>\n\n```ruby\n<%= system('bad') %>\n```\n")
    assert_includes html,'&lt;script&gt;'
    refute_includes html,'<script>'
    assert_includes html,'&lt;%='
  end
  def test_neural_optimizer_reduces_loss_and_changes_actual_weights
    network=NevaehIntelligences::Neural::Network.build(examples:examples,hidden_size:8,vocabulary_limit:64)
    before=network.epoch(examples);fingerprint=NevaehIntelligences::CanonicalJSON.dump(network.state)
    10.times { |epoch| network.epoch(examples,learning_rate:0.08,seed:epoch) }
    assert_operator network.epoch(examples),:<,before/2
    refute_equal fingerprint,NevaehIntelligences::CanonicalJSON.dump(network.state)
    assert_operator network.state['updates'],:>,0
    assert_equal 'Hello welcome to the studio',network.generate(prompt:'hello person',temperature:0)['text']
  end
  def test_training_persists_evaluates_and_explicitly_activates_checkpoint
    model,run,checkpoint=trained
    assert_equal 'completed',run.status
    assert_equal 'verified',checkpoint.status
    assert_nil model.active_checkpoint_id
    assert_operator checkpoint.metrics['training_loss'],:<,checkpoint.metrics['initial_loss']
    assert_operator checkpoint.metrics['heldout_examples'],:>,0
    NevaehIntelligences::Neural::Training.activate!(checkpoint:checkpoint,actor:@actor)
    assert_equal checkpoint.id,model.reload.active_checkpoint_id
    refute checkpoint.update(weights:{})
    assert_includes model.neural_reply(prompt:'hello person',temperature:0)['text'],'Hello'
  end
  def test_training_requires_review_and_idempotent_request_keys
    model=NevaehLanguageModel.create!(name:'Native')
    dataset=approved_dataset
    first=NevaehIntelligences::Neural::Training.request!(model:model,dataset:dataset,actor:@actor,epochs:2,request_key:'training-request-1')
    second=NevaehIntelligences::Neural::Training.request!(model:model,dataset:dataset,actor:@actor,epochs:2,request_key:'training-request-1')
    assert_equal first.id,second.id
    dataset.update!(examples:examples.reverse)
    assert_equal 'draft',dataset.reload.status
    assert_raises(ArgumentError) { NevaehIntelligences::Neural::Training.request!(model:model,dataset:dataset,actor:@actor,epochs:2,request_key:'training-request-2') }
    NevaehIntelligences::Neural::Training.run!(first)
    assert_equal 'failed',first.reload.status
  end
  def test_instance_training_lease_prevents_two_simultaneous_trainers
    first_model=NevaehLanguageModel.create!(name:'First trainer')
    second_model=NevaehLanguageModel.create!(name:'Second trainer')
    dataset=approved_dataset
    first=NevaehIntelligences::Neural::Training.request!(model:first_model,dataset:dataset,actor:@actor,epochs:2,request_key:'lease-first-1')
    second=NevaehIntelligences::Neural::Training.request!(model:second_model,dataset:dataset,actor:@actor,epochs:2,request_key:'lease-second-1')
    first.update!(status:'running',heartbeat_at:Time.current,lease_token:'existing-lease')
    NevaehIntelligences::Neural::Training.run!(second)
    assert_equal 'queued',second.reload.status
    assert_equal 'existing-lease',first.reload.lease_token
    assert_equal 1,NevaehTrainingRun.where(status:'running').count
    first.update!(heartbeat_at:10.minutes.ago)
    NevaehIntelligences::Neural::Training.sweep!
    assert_equal 'queued',first.reload.status
    assert_nil first.lease_token
  end
  def test_cancelled_training_is_not_restarted
    model=NevaehLanguageModel.create!(name:'Native')
    run=NevaehIntelligences::Neural::Training.request!(model:model,dataset:approved_dataset,actor:@actor,epochs:2,request_key:'training-cancel-1')
    run.update!(status:'cancelled')
    NevaehIntelligences::Neural::Training.run!(run)
    assert_equal 'cancelled',run.reload.status
    assert_nil run.checkpoint
  end
  def test_conversation_uses_checkpoint_and_is_private_and_idempotent
    model,run,checkpoint=trained
    NevaehIntelligences::Neural::Training.activate!(checkpoint:checkpoint,actor:@actor)
    conversation=NevaehConversation.create!(user:@actor,nevaeh_language_model:model)
    turn=conversation.reply!(actor:@actor,prompt:'hello person',request_key:'chat-request-1')
    again=conversation.reply!(actor:@actor,prompt:'hello person',request_key:'chat-request-1')
    assert_equal turn.id,again.id
    assert_equal checkpoint.id,turn.checkpoint_id
    assert_equal 1,conversation.turns.count
    assert_raises(ArgumentError) { conversation.reply!(actor:User.create!(role:'employee'),prompt:'hello',request_key:'chat-request-2') }
  end
  def test_neural_writing_respects_internal_model_visibility
    model,run,checkpoint=trained
    NevaehIntelligences::Neural::Training.activate!(checkpoint:checkpoint,actor:@actor)
    profile=NevaehWritingProfile.create!(name:'Neural captions',format:'caption',provider:'neural',language_model:model,instructions:'Closing: {call_to_action}')
    employee=User.create!(role:'employee')
    assert_raises(ArgumentError) { NevaehIntelligences::WritingEngine.generate(format:'caption',context:{'topic'=>'hello'},profile:profile.contract,actor:employee) }
    result=NevaehIntelligences::WritingEngine.generate(format:'caption',context:{'topic'=>'hello','call_to_action'=>'Join us.'},profile:profile.contract,actor:@actor)
    assert_equal 'neural',result['provider']
    assert_equal checkpoint.id,result.dig('inference','checkpoint_id')
    assert_includes result['text'],'Join us.'
    model.reload.update!(visibility:'shared')
    assert model.available_to?(employee)
  end
  def test_training_and_evaluation_prompts_do_not_overlap
    repeated=examples+[examples.first.dup]
    train,heldout=NevaehIntelligences::Neural::Training.split(repeated)
    assert_empty train.map { |row| row['prompt'] } & heldout.map { |row| row['prompt'] }
  end
  def test_synthetic_corpus_is_reviewable_and_provenance_is_explicit
    generated=NevaehIntelligences::Neural::CorpusFactory.generate(count:10,topic:'Studio')
    assert_equal 10,generated[:examples].length
    assert generated[:provenance][:fictional]
    assert_equal false,generated[:provenance][:reviewed]
    assert generated[:examples].all? { |row| row.keys.sort == %w[prompt response] }
  end
end

class NevaehDigitalFactoryRenderTest < Minitest::Test
  def teardown
    NevaehConstruction.update_all(active_release_id:nil);NevaehLanguageModel.update_all(active_checkpoint_id:nil)
    [NevaehConversationTurn,NevaehConversation,NevaehLanguageCheckpoint,NevaehTrainingRun,NevaehTrainingDataset,NevaehWritingProfile,NevaehLanguageModel,NevaehConstructionRelease,NevaehConstruction].each(&:delete_all)
  end
  def test_factory_training_conversation_library_and_shared_help_render
    view=ActionView::Base.with_empty_template_cache.new(ActionView::LookupContext.new([File.join(ROOT,'app/views')]),{},nil)
    view.extend(NevaehControlCenterHelper);view.extend(NevaehHelpHelper)
    class << view
      def current_user = @preview_user
      def can?(*args) = true
      def main_app = self
      def dymond_dash = self
      def protect_against_forgery? = false
      def params = {}
      def request = OpenStruct.new(path:'/employee/nevaeh/factory')
      def url_for(value) = value.is_a?(String) ? value : '/preview'
      def method_missing(name,*args,**kwargs,&block)
        return '/employee/nevaeh/factory' if name == :employee_nevaeh_factory_path
        return '/dashboard' if name == :root_path
        return '/'+name.to_s.sub(/_path$/,'').tr('_','/') if name.to_s.end_with?('_path')
        super
      end
      def respond_to_missing?(name,*args) = name.to_s.end_with?('_path') || super
    end
    actor=User.create!(role:'super_admin');view.instance_variable_set(:@preview_user,actor)
    definition={'input_schema'=>{'name'=>'string'},'steps'=>[{'op'=>'template','field'=>'greeting','text'=>'Welcome, {name}.'}]}
    record=NevaehConstruction.create!(creator:actor,name:'Welcome message',key:'render_welcome',definition:definition,sample_tests:[{'inputs'=>{'name'=>'Marlon'},'expected'=>{'name'=>'Marlon','greeting'=>'Welcome, Marlon.'}}])
    model=NevaehLanguageModel.create!(name:'Nevaeh Conversation')
    dataset=NevaehTrainingDataset.create!(creator:actor,status:'approved',name:'Fictional Studio conversations',examples:(1..5).map { |n| {'prompt'=>"Hello #{n}",'response'=>'Hello, what would you like to create?'} })
    release=NevaehIntelligences::Factory::Compiler.build!(construction:record,actor:actor)
    NevaehIntelligences::Factory::Compiler.activate!(release:release,actor:actor)
    run=NevaehIntelligences::Neural::Training.request!(model:model,dataset:dataset,actor:actor,epochs:10,request_key:'render-training-1')
    NevaehIntelligences::Neural::Training.run!(run)
    NevaehIntelligences::Neural::Training.activate!(checkpoint:run.reload.checkpoint,actor:actor)
    conversation=NevaehConversation.create!(user:actor,nevaeh_language_model:model,title:'Planning a Studio production')
    conversation.reply!(actor:actor,prompt:'Hello Nevaeh',request_key:'render-conversation-1')
    docs=NevaehIntelligences::SoftwareLibrary.new.documents
    values={construction:record,constructions:[record],datasets:[dataset],dataset:dataset,models:[model],language_model:model.reload,training_runs:[run.reload],conversations:[conversation],conversation:conversation,documents:docs,sections:docs.map { |doc| doc[:section] }.uniq,document:docs.find { |doc| doc[:path]=='docs/nevaeh/digital_factory.md' }}
    values.each { |key,value| view.instance_variable_set("@#{key}",value) }
    %w[construction training conversation].each do |tab|
      view.instance_variable_set(:@tab,tab)
      html=view.render(template:'employee/nevaeh_factory/index')
      assert_includes html,'data-factory'
      assert_includes html,'Digital Factory'
      write_preview(tab,html,view) if ENV['NEVAEH_FACTORY_PREVIEW_DIR']
    end
    html=view.render(template:'employee/software_library/index')
    assert_includes html,'Software Library'
    assert_includes html,'Train actual neural weights'
    write_preview('library',html,view) if ENV['NEVAEH_FACTORY_PREVIEW_DIR']
    help=view.render(partial:'shared/nevaeh_contextual_help')
    assert_includes help,'data-nevaeh-help-dialog'
  end
  def write_preview(name,html,view)
    directory=ENV.fetch('NEVAEH_FACTORY_PREVIEW_DIR');FileUtils.mkdir_p(directory)
    head='<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="csrf-token" content="preview"><link rel="stylesheet" href="/lightek/nevaeh/control-center.css"><link rel="stylesheet" href="/lightek/nevaeh/factory.css"><script src="/lightek/nevaeh/factory.js" defer></script><style>body{margin:0;padding:30px;background:#16151c;color:#eee;font-family:system-ui}*{box-sizing:border-box}</style>'
    File.write(File.join(directory,"#{name}.html"),"<!doctype html><html><head>#{head}</head><body><div class='dd-content'>#{html}</div>#{view.render(partial:'shared/nevaeh_contextual_help')}</body></html>")
  end
end
