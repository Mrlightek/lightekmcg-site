# frozen_string_literal: true
require_relative 'nevaeh_salah_study_test'
require File.join(ROOT, 'db/migrate/20261114230000_create_nevaeh_manual_learning')
CreateNevaehManualLearning.new.migrate(:up)
%w[services/nevaeh_os/resources services/nevaeh_os/guide services/nevaeh_os/language_contract
 models/nevaeh_manual_build models/nevaeh_language_binding models/nevaeh_learning_plan
 services/nevaeh_os/language services/nevaeh_intelligences/manual_bindings
 services/nevaeh_intelligences/manuals services/nevaeh_intelligences/learning_plans
 jobs/nevaeh_intelligences/manual_learn_job].each { |path| require File.join(ROOT, 'app', path) }

class NevaehManualLearningTest < Minitest::Test
  def setup
    @actor = User.create!(role: 'super_admin')
    @temporary = Dir.mktmpdir('nevaeh-manuals')
    FileUtils.mkdir_p(File.join(@temporary, 'docs/nevaeh/tutorials'))
    @path = File.join(@temporary, 'docs/nevaeh/tutorials/commands.md')
    File.write(@path, "# Working manual\n" + (1..10).map { |n| "## Greeting #{n}\nHello welcome to the studio.\n" }.join)
    @library = NevaehIntelligences::SoftwareLibrary.new(root: @temporary)
  end
  def teardown
    NevaehLearningPlan.delete_all; NevaehLanguageBinding.delete_all; NevaehManualBuild.delete_all
    NevaehLanguageModel.update_all(active_checkpoint_id: nil)
    [NevaehConversationTurn, NevaehConversation, NevaehLanguageCheckpoint, NevaehTrainingRun, NevaehTrainingDataset, NevaehWritingProfile, NevaehLanguageModel].each(&:delete_all)
    FileUtils.remove_entry(@temporary)
  end
  def with_library
    NevaehIntelligences::SoftwareLibrary.stub(:new, @library) { yield }
  end
  def build
    record = NevaehManualBuild.create!(creator: @actor, name: 'Installed manuals fixture')
    catalog = [{key:'fixture.echo',title:'Echo message',topic:'commands',source:'installed capability',availability:'connected',coverage:'fields',inputs:{'message'=>'string'}},
      {key:'fixture.missing',title:'Needs adapter',topic:'platform',source:'installed capability',availability:'adapter_needed',coverage:'schema_needed'}]
    NevaehOs::Guide.stub(:catalog, catalog) { NevaehIntelligences::Manuals.build!(record, library: @library) }
    record.reload
  end
  def binding(command: {'kind'=>'project','name'=>'{name}'}, pattern: 'make a studio project called {name}')
    doc = @library.documents.first
    NevaehLanguageBinding.create!(creator: @actor, name: 'Create Studio project', patterns: [pattern], slots: {'name'=>'string'}, command_template: command,
      source_refs: [{'path'=>doc[:path],'sha256'=>doc[:sha256],'title'=>doc[:title]}])
  end
  def test_bulk_import_preserves_source_parts_and_generates_drafts_and_real_gaps
    result = build
    assert_equal 'ready', result.status, result.error
    assert_equal 1, result.manifest.length
    assert_operator result.dataset_ids.length, :>, 0
    assert_operator result.bindings.count, :>, 3
    assert result.bindings.all? { |row| row.status == 'draft' }
    assert_equal 'fixture.missing', result.coverage['gaps'].first['key']
    pairs = result.dataset_ids.flat_map { |id| NevaehTrainingDataset.find(id).examples }
    assert_equal File.read(@path), pairs.map { |row| row['response'] }.join
    assert pairs.all? { |row| NevaehIntelligences::Neural::Network.tokens(row['response']).length <= 48 }
    count = NevaehTrainingDataset.count
    NevaehIntelligences::Manuals.build!(result, library: @library)
    assert_equal count, NevaehTrainingDataset.count
  end
  def test_manual_provenance_blocks_changed_files_and_edited_examples
    result = build
    dataset = NevaehTrainingDataset.find(result.dataset_ids.first)
    NevaehIntelligences::Manuals.verify_dataset!(dataset, library: @library)
    File.write(@path, 'Updated documentation')
    assert_raises(ArgumentError) { NevaehIntelligences::Manuals.verify_dataset!(dataset, library: @library) }
    dataset.update!(examples: dataset.examples.reverse)
    assert_raises(ArgumentError) { NevaehIntelligences::Manuals.verify_dataset!(dataset, library: @library) }
  end
  def test_typed_phrase_binds_quoted_data_and_never_evaluates_it
    row = binding
    with_library do
      NevaehOs::Language.activate!(binding: row, actor: @actor)
      value = '"Launch #{raise 123}"'
      result = NevaehOs::Language.resolve("make a studio project called #{value}", actor: @actor)
      assert_equal 'Launch #{raise 123}', result['command']['name']
      assert_equal row.id, result['command']['language_binding']['id']
      NevaehOs::Language.guard!(result['command'], actor: @actor)
      row.update!(patterns: ['start a production called {name}'])
      assert_equal 'draft', row.reload.status
      assert_raises(ArgumentError) { NevaehOs::Language.guard!(result['command'], actor: @actor) }
    end
  end
  def test_ambiguous_phrases_and_source_drift_never_dispatch
    first = binding
    second = binding(command: {'kind'=>'ticket','text'=>'{name}'})
    with_library do
      [first, second].each { |row| NevaehOs::Language.activate!(binding: row, actor: @actor) }
      result = NevaehOs::Language.resolve('make a studio project called Example', actor: @actor)
      assert_equal 'needs_clarification', result['status']
      refute result.key?('command')
      second.update!(status: 'paused')
      File.write(@path, 'Updated source')
      result = NevaehOs::Language.resolve('make a studio project called Example', actor: @actor)
      assert_equal 'needs_clarification', result['status']
      client = User.create!(role: 'client')
      assert_nil NevaehOs::Language.resolve('make a studio project called Example', actor: client)
    end
  end
  def test_recurring_phrase_produces_an_agent_task_with_typed_inner_command
    row = binding
    with_library do
      NevaehOs::Language.activate!(binding: row, actor: @actor)
      result = NevaehOs::Language.resolve('every 60 minutes, make a studio project called Example', actor: @actor, agent_ref: 'sage')
      assert_equal 'agent_task', result['command']['kind']
      assert_equal 'sage', result['command']['agent_ref']
      assert_equal 60, result['command']['interval_minutes']
      assert_equal 'Example', result['command']['command']['name']
      assert_raises(ArgumentError) { NevaehOs::Language.resolve('every 1 minute, make a studio project called Example', actor: @actor) }
    end
  end
  def test_unsafe_template_shapes_are_rejected
    row = binding
    refute row.update(command_template: {'kind'=>'console','expression'=>'{name}'})
    row.reload
    refute row.update(command_template: {'kind'=>'project','name'=>'prefix {name}'})
    row.reload
    refute row.update(patterns: ['{name}{name}'])
    row.reload
    refute row.update(command_template: {'kind'=>'project'})
  end
  def test_source_chunks_split_long_code_tokens_without_truncation
    text = 'https://example.org/' + ('very.long_path/' * 200)
    parts = NevaehIntelligences::Manuals.pieces(text)
    assert_equal text, parts.join
    assert parts.all? { |part| NevaehIntelligences::Neural::Network.tokens(part).length <= 48 }
  end
  def test_plan_uses_real_training_and_activates_before_the_next_batch
    result = NevaehManualBuild.create!(creator: @actor, name: 'Plan fixture', status: 'ready')
    doc = @library.documents.first
    datasets = (1..2).map do |batch|
      pairs = (1..10).map { |n| {'prompt'=>"hello person #{batch} number #{n}",'response'=>'hello welcome to the studio'} }
      NevaehTrainingDataset.create!(creator: @actor, name: "Batch #{batch}", status: 'approved', examples: pairs,
        provenance: {'source'=>'installed_manuals','manual_build_id'=>result.id,'examples_sha256'=>Digest::SHA256.hexdigest(NevaehIntelligences::CanonicalJson.dump(pairs)),
          'citations'=>[{'path'=>doc[:path],'sha256'=>doc[:sha256]}]})
    end
    result.update!(dataset_ids: datasets.map(&:id))
    model = NevaehLanguageModel.create!(name: 'Manual model', hidden_size: 8, vocabulary_limit: 64)
    with_library do
      plan = NevaehIntelligences::LearningPlans.request!(build: result, model: model, actor: @actor, epochs: 12)
      NevaehIntelligences::LearningPlans.sweep!
      first = plan.reload.active_training_run
      NevaehIntelligences::Neural::Training.run!(first)
      assert_equal true, first.reload.metrics['acceptance_passed'], first.error
      NevaehIntelligences::LearningPlans.sweep!
      second = plan.reload.active_training_run
      assert_equal 1, plan.position
      assert_equal first.checkpoint.id, second.snapshot['parent_checkpoint_id']
      assert_equal first.checkpoint.id, model.reload.active_checkpoint_id
      NevaehIntelligences::Neural::Training.run!(second)
      NevaehIntelligences::LearningPlans.sweep!
      assert_equal 'completed', plan.reload.status, plan.error
      assert_equal 2, plan.position
      assert_nil plan.active_training_run
    end
  end
  def test_all_installed_manuals_can_be_batched_without_dropping_their_text
    real_library = NevaehIntelligences::SoftwareLibrary.new(root: ROOT)
    result = NevaehManualBuild.create!(creator:@actor,name:'Installed documentation verification')
    NevaehOs::Guide.stub(:catalog,[]) { NevaehIntelligences::Manuals.build!(result,library:real_library) }
    assert_equal 'ready', result.reload.status, result.error
    assert_operator result.coverage['document_count'], :>=, 118
    recovered = Hash.new { |hash,key| hash[key] = +'' }
    result.dataset_ids.each do |id|
      dataset = NevaehTrainingDataset.find(id)
      assert dataset.valid?
      NevaehIntelligences::Manuals.verify_dataset!(dataset,documents:real_library.documents)
      dataset.examples.zip(dataset.provenance['citations']).each { |row,citation| recovered[citation['path']] << row['response'] }
    end
    real_library.documents.each { |doc| assert_equal doc[:body], recovered[doc[:path]], doc[:path] unless doc[:body].strip.empty? }
    puts "Installed manuals verified: #{result.coverage['document_count']} documents, #{result.coverage['training_parts']} parts, #{result.dataset_ids.length} batches"
  end
  def test_documented_json_examples_fill_a_missing_registry_input_schema_as_drafts
    File.write(@path, "# Example API\nfixture.echo {\"message\":\"Example\",\"frame\":0}\n")
    record = NevaehManualBuild.create!(creator:@actor,name:'Documented API binding')
    catalog = [{key:'fixture.echo',title:'Echo message',topic:'commands',source:'installed capability',availability:'connected',coverage:'schema_needed',inputs:nil}]
    NevaehOs::Guide.stub(:catalog,catalog) { NevaehIntelligences::ManualBindings.candidates(build:record,documents:@library.documents,actor:@actor) }
    row = record.bindings.find_by!(name:'Echo message')
    assert_equal({'message'=>'string','frame'=>'integer'},row.slots)
    assert_equal 'draft',row.status
    assert_equal 0,NevaehOs::LanguageContract.match(row,'echo message message Hello frame 0').first['payload']['frame']
  end
  def test_pause_cancels_a_queued_plan_and_resume_uses_a_new_attempt
    result = build
    with_library do
      NevaehIntelligences::Manuals.approve!(build:result,actor:@actor)
      model = NevaehLanguageModel.create!(name:'Paused plan',hidden_size:8,vocabulary_limit:128)
      plan = NevaehIntelligences::LearningPlans.request!(build:result,model:model,actor:@actor,epochs:2)
      NevaehIntelligences::LearningPlans.sweep!
      first = plan.reload.active_training_run
      NevaehIntelligences::LearningPlans.pause!(plan:plan,actor:@actor)
      assert_equal 'cancelled',first.reload.status
      NevaehIntelligences::LearningPlans.sweep!
      NevaehIntelligences::LearningPlans.resume!(plan:plan.reload,actor:@actor)
      NevaehIntelligences::LearningPlans.sweep!
      refute_equal first.id,plan.reload.active_training_run_id
      assert_equal 1,plan.attempt
      assert_equal 0,plan.position
    end
  end
  def test_manual_workspace_renders_its_corpus_training_and_teaching_controls
    result = build
    view = ActionView::Base.with_empty_template_cache.new(ActionView::LookupContext.new([File.join(ROOT,'app/views')]),{},nil)
    view.extend(NevaehHelpHelper)
    class << view
      def main_app = self
      def protect_against_forgery? = false
      def url_for(value) = value.is_a?(String) ? value : '/preview'
      def method_missing(name,*args,**kwargs,&block)
        return '/'+name.to_s if name.to_s.end_with?('_path')
        super
      end
      def respond_to_missing?(name,*args) = name.to_s.end_with?('_path') || super
    end
    {manual_builds:[result],manual_build:result,language_bindings:result.bindings.to_a,language_binding:result.bindings.first,
      models:[],learning_plans:[],documents:@library.documents}.each { |key,value| view.instance_variable_set("@#{key}",value) }
    html = view.render(partial:'employee/nevaeh_factory/manual_learning')
    assert_includes html,'Train approved batches sequentially'
    assert_includes html,'Activate reviewed conversational phrases'
    assert_includes html,'Teach a phrase'
    assert_includes html,'Adapter or input-contract gaps'
    assert_includes html,'Sequential learning plans'
  end
end
