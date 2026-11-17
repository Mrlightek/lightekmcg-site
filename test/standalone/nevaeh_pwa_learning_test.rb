require_relative 'nevaeh_manual_learning_test'
require File.join(ROOT, 'app/services/nevaeh_intelligences/pwa_learning')
class NevaehPwaLearningTest < NevaehManualLearningTest
  NevaehManualLearningTest.instance_methods(false).grep(/^test_/).each { |name| undef_method(name) }
  def setup
    super
    NevaehIntelligences::PwaLearning::PATHS.each do |relative|
      target=File.join(@temporary,relative)
      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.cp(File.join(ROOT,relative),target)
    end
  end
  def prepare
    NevaehIntelligences::PwaLearning.prepare!(actor:@actor,library:@library)
  end
  def model(visibility:'internal')
    NevaehLanguageModel.create!(name:'PWA learning test',hidden_size:8,vocabulary_limit:128,enabled:true,visibility:visibility)
  end
  def test_pack_builds_actual_policy_and_audit_without_creating_operating_bindings
    result=prepare
    assert_equal 'ready',result.status
    assert_equal NevaehIntelligences::PwaLearning::PATHS,result.manifest.map{|r|r['path']}
    assert_operator result.dataset_ids.size,:>,0
    assert_empty result.bindings
    assert result.dataset_ids.all?{|id|NevaehTrainingDataset.find(id).status=='draft'}
    responses=result.dataset_ids.flat_map{|id|NevaehTrainingDataset.find(id).examples.map{|r|r['response']}}.join
    assert_includes responses,'100%'
    assert_includes responses,'1,000 views'
    assert_includes responses,'not implemented'
  end
  def test_repeated_preparation_reuses_the_same_source_build_and_datasets
    first=prepare
    second=prepare
    assert_equal first.id,second.id
    assert_equal first.dataset_ids,second.dataset_ids
    assert_equal 1,NevaehManualBuild.where(creator:@actor).count
  end
  def test_reviewed_training_uses_existing_plan_without_claiming_a_checkpoint
    result=prepare
    selected=model
    with_library do
      plan=NevaehIntelligences::PwaLearning.train!(build:result,model:selected,actor:@actor,epochs:2)
      assert_equal 'running',plan.status
      assert_equal result.dataset_ids,plan.dataset_ids
      assert_equal 0,plan.position
      assert_nil selected.reload.active_checkpoint
      assert result.dataset_ids.all?{|id|NevaehTrainingDataset.find(id).status=='approved'}
      assert_equal plan.id,NevaehIntelligences::PwaLearning.train!(build:result,model:selected,actor:@actor,epochs:2).id
    end
  end
  def test_changed_policy_blocks_training_and_requires_a_new_build
    result=prepare
    File.open(File.join(@temporary,NevaehIntelligences::PwaLearning::PATHS.first),'a'){|f|f.write("\nPolicy changed.\n")}
    with_library do
      error=assert_raises(ArgumentError){NevaehIntelligences::PwaLearning.train!(build:result,model:model,actor:@actor,epochs:2)}
      assert_match(/sources changed/,error.message)
    end
    assert_equal 0,NevaehLearningPlan.where(nevaeh_manual_build:result).count
    refute_equal result.id,prepare.id
  end
  def test_missing_source_is_not_silently_replaced_by_unrelated_manuals
    File.delete(File.join(@temporary,NevaehIntelligences::PwaLearning::PATHS.last))
    assert_raises(ArgumentError){prepare}
  end
  def test_operational_source_training_rejects_shared_models
    result=prepare
    with_library{assert_raises(ArgumentError){NevaehIntelligences::PwaLearning.train!(build:result,model:model(visibility:'shared'),actor:@actor,epochs:2)}}
    assert_equal 0,NevaehLearningPlan.where(nevaeh_manual_build:result).count
  end
end
