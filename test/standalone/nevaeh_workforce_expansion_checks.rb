require_relative 'nevaeh_manual_learning_test'
require File.join(ROOT,'app/services/nevaeh_os/improvements')
require File.join(ROOT,'app/services/nevaeh_os/goals')
class NevaehWorkforceExpansionChecks < NevaehManualLearningTest
  def self.runnable_methods = instance_methods(false).grep(/^test_/).map(&:to_s)
  def test_librarian_task_creates_real_draft_batches_and_phrases_from_installed_manuals
    queued=[]
    result=NevaehIntelligences::ManualLearnJob.stub(:perform_later,->(id) { queued<<id }) { NevaehOs::Improvements.perform!(@actor,'corpus') }
    assert_equal [result['manual_build_id']],queued
    corpus=NevaehManualBuild.find(result['manual_build_id'])
    catalog=[{key:'fixture.echo',title:'Echo message',topic:'commands',source:'installed capability',availability:'connected',coverage:'fields',inputs:{'message'=>'string'}}]
    NevaehOs::Guide.stub(:catalog,catalog) { NevaehIntelligences::Manuals.build!(corpus,library:@library) }
    assert_equal 'ready',corpus.reload.status,corpus.error
    assert_operator corpus.dataset_ids.size,:>,0
    assert corpus.dataset_ids.all? { |id| NevaehTrainingDataset.find(id).status=='draft' }
    assert_operator corpus.bindings.count,:>,0
    assert corpus.bindings.all? { |phrase| phrase.status=='draft' }
  end
  def test_language_tester_accepts_current_sources_and_reports_drift_without_activation
    phrase=binding
    with_library do
      NevaehOs::Language.activate!(binding:phrase,actor:@actor)
      assert NevaehOs::Improvements.perform!(@actor,'language_check')['success']
      File.write(@path,'Changed installed procedure')
      result=NevaehOs::Improvements.perform!(@actor,'language_check')
      refute result['success'];assert_equal false,result['checks'].find { |row| row[:id]==phrase.id }[:passed]
      assert_equal 'active',phrase.reload.status
    end
  end
  def test_constructed_worker_builds_executable_ruby_and_goal_accepts_only_verified_samples
    record=NevaehConstruction.create!(creator:@actor,name:'Greeting service',key:'worker_greeting',definition:{'input_schema'=>{'name'=>'string'},'steps'=>[{'op'=>'normalize','field'=>'name','mode'=>'strip'},{'op'=>'template','field'=>'greeting','text'=>'Welcome, {name}.'},{'op'=>'require','fields'=>['greeting']}]},sample_tests:[{'inputs'=>{'name'=>' Marlon '},'expected'=>{'name'=>'Marlon','greeting'=>'Welcome, Marlon.'}}])
    release=NevaehIntelligences::Factory::Compiler.build!(construction:record,actor:@actor)
    assert_equal 'verified',release.status
    actual=NevaehIntelligences::Factory::Compiler.load!(release)::Service.call(inputs:{'name'=>' Marlon '})
    assert_equal 'Welcome, Marlon.',actual['greeting']
    receipt={status:'completed',result:{release_id:release.id,status:release.status,verification:release.verification}}
    assert_equal 'completed',NevaehOs::Goals.verdict(receipt,{'kind'=>'build'},[]).first
    receipt[:result][:verification]={'samples'=>[{'passed'=>false}]}
    assert_equal 'blocked',NevaehOs::Goals.verdict(receipt,{'kind'=>'build'},[]).first
  end
end
