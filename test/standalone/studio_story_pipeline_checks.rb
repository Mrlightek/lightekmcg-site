require_relative 'studio_director_finishing_checks'
require File.join(ROOT,'app/services/nevaeh_os/agent_workforce')
require File.join(ROOT,'app/jobs/nevaeh_os/agent_run_job')
class StudioStoryPipelineChecks < StudioDirectorFinishingChecks
  def self.runnable_methods = instance_methods(false).grep(/^test_/).map(&:to_s)
  def story_values(production)
    scene=production.studio_scenes.first
    cameras=scene.scene_objects.where(object_type:'camera').limit(2).to_a
    {'scene_id'=>scene.id,'characters'=>[{'id'=>'a','name'=>'Amina','template'=>'aries:pressure','goal'=>'protect the workshop','knows'=>['The door is locked'],'secret'=>'I hid the key'},{'id'=>'b','name'=>'Bilal','birth_date'=>'1990-12-25','goal'=>'find the missing key','knows'=>[]}],
      'events'=>[{'text'=>'The spare key is under the desk','visible_to'=>['a']},{'text'=>'The lights go out','visible_to'=>%w[a b]}],
      'viewpoint_cameras'=>{'a'=>cameras.first.id,'b'=>cameras.last.id}}
  end
  def test_story_workers_share_a_persisted_state_and_create_viewpoint_scripts_through_real_dispatch
    production=Production.find(directed['production_id']);values=story_values(production);key=SecureRandom.uuid
    first=Studio::Director::StoryPipeline.start!(production:production,actor:@alice,values:values,request_key:key)
    assert_equal first,Studio::Director::StoryPipeline.start!(production:production,actor:@alice,values:values,request_key:key)
    op=StudioOperation.find(first['story_operation_id'])
    4.times do
      Studio::Director::StoryPipeline.tick!(op.reload)
      entry=op.reload.manifest['stages'].values.find { |row| row['status']=='queued' }
      run=NevaehAgentRun.find(entry.fetch('agent_run_id'))
      NevaehOs::AgentWorkforce.execute!(run)
      NevaehOs::Worker.perform('execute',{'action_id'=>run.reload.nevaeh_os_action_id})
    end
    Studio::Director::StoryPipeline.tick!(op.reload)
    assert_equal 'completed',op.reload.status
    assert_equal 4,op.manifest['stages'].size
    assert op.manifest['stages'].values.all? { |row| row['status']=='completed' && row['agent_worker_id'] && row['agent_run_id'] }
    simulation=op.manifest['simulation']
    refute simulation.last['beats'].first['observed']
    refute_includes simulation.last['beats'].first['known_facts'],'The spare key is under the desk'
    assert_includes simulation.first['beats'].first['known_facts'],'The spare key is under the desk'
    scene=op.studio_scene.reload
    assert_includes scene.settings.dig('workspace','story','scriptDraft'),'BILAL'
    refute_includes scene.settings.dig('workspace','story','scriptDraft'),'I hid the key'
    assert_equal values['viewpoint_cameras']['a'],scene.settings.dig('shot_board','shots',0,'camera_id')
    assert_includes scene.settings.dig('shot_board','shots',0,'notes'),'Amina'
    assert_equal 36,Studio::Director::Personality.catalog.size
    assert_equal 'capricorn:balanced',op.manifest['characters'].last.dig('personality','key')
  end
  def test_story_stale_edits_paused_workers_and_unknown_viewpoints_block_without_overwriting
    production=Production.find(directed['production_id']);values=story_values(production)
    receipt=Studio::Director::StoryPipeline.start!(production:production,actor:@alice,values:values,request_key:SecureRandom.uuid)
    op=StudioOperation.find(receipt['story_operation_id']);Studio::Director::StoryPipeline.tick!(op)
    scene=op.studio_scene;scene.update!(settings:scene.settings.merge('human_edit'=>'preserve'))
    assert_raises(ArgumentError) { Studio::Director::StoryPipeline.step!(production:production,actor:@alice,values:{'story_operation_id'=>op.id,'stage'=>'characters'},request_key:SecureRandom.uuid) }
    assert_equal 'preserve',scene.reload.settings['human_edit']
    assert_raises(ActiveRecord::RecordNotFound) { Studio::Director::StoryPipeline.find!(op.id,actor:@bob) }
    values['events'][0]['visible_to']=['unlisted']
    assert_raises(ArgumentError) { Studio::Director::StoryPipeline.start!(production:production,actor:@alice,values:values,request_key:SecureRandom.uuid) }
  end
  def test_scene_relations_reject_missing_foreign_and_parent_cycles_but_allow_reciprocal_gaze
    production=short_episode;scene=production.studio_scenes.first
    a=scene.scene_objects.create!(name:'A',object_type:'cube',definition:{'location'=>[-1,0,0]})
    b=scene.scene_objects.create!(name:'B',object_type:'cube',definition:{'location'=>[1,0,0]})
    klass=Studio::Director::Relationships
    assert_equal 2,klass.normalize(scene,[{'object_id'=>a.id,'look_at'=>b.id},{'object_id'=>b.id,'look_at'=>a.id}]).size
    assert_raises(ArgumentError) { klass.normalize(scene,[{'object_id'=>a.id,'relative_to'=>b.id},{'object_id'=>b.id,'relative_to'=>a.id}]) }
    assert_raises(ArgumentError) { klass.normalize(scene,[{'object_id'=>a.id,'relative_to'=>999999}]) }
    assert_raises(ArgumentError) { klass.normalize(scene,[{'object_id'=>a.id,'look_at'=>b.id,'personal_space'=>-1}]) }
    camera=scene.scene_objects.where(object_type:'camera').first
    result=Studio::Director::Finishing.blocking!(production:production,actor:@alice,values:{'scene_id'=>scene.id,'lock_version'=>scene.lock_version,'personal_space'=>1.2,'collision_detection'=>true,'relationships'=>[{'object_id'=>camera.id,'relative_to'=>a.id,'offset'=>[0,-5,1.5],'look_at'=>a.id,'depth_of_field'=>true}]},request_key:SecureRandom.uuid)
    assert_equal 'prepared',result['status']
    assert_equal 1.2,scene.reload.settings.dig('spatial_direction','personal_space')
    assert camera.reload.definition.dig('story_relation','depth_of_field')
  end
  def test_series_identity_and_two_speaker_staging_preserve_faces_spacing_and_listener_targets
    cast=ready_actor
    first=directed({'series_key'=>'family_business','dialogue'=>[{'scene'=>1,'speaker'=>'Amina','text'=>'Hello.'},{'scene'=>1,'speaker'=>'Bilal','text'=>'Welcome.'}]})
    production=Production.find(first['production_id']);voice=StudioOperation.find(first['voice_operations'].first['id'])
    ScreenplayEngine::AudioSynthesizer.stub(:synthesize!,voice_fixture) { StudioDirectedVoiceJob.perform_now(voice.id) }
    2.times do |index|
      scene=voice.studio_scene.reload
      Studio::Director::Finishing.animate!(production:production,actor:@alice,values:{'scene_id'=>scene.id,'cast_asset_id'=>cast.id,'voice_operation_id'=>voice.id,'cue_index'=>index,'lock_version'=>scene.lock_version},request_key:SecureRandom.uuid)
    end
    assert_in_delta 0.8,voice.reload.manifest.dig('dialogue',1,'start'),0.03
    scene=voice.studio_scene.reload;actors=scene.scene_objects.select { |object| object.definition['director_speaker'] }
    assert_equal [-1.0,1.0],actors.map { |object| object.definition['location'][0] }.sort
    assert_equal actors.last.id,actors.first.definition.dig('story_relation','look_at')
    assert_equal actors.first.id,actors.last.definition.dig('story_relation','look_at')
    Studio::Director::Finishing.validate_continuity!(production.reload,scene)
    second=directed({'series_key'=>'family_business','episode_number'=>2,'dialogue'=>[{'scene'=>1,'speaker'=>'Amina','text'=>'Again.'}]})
    voice=StudioOperation.find(second['voice_operations'].first['id'])
    ScreenplayEngine::AudioSynthesizer.stub(:synthesize!,voice_fixture) { StudioDirectedVoiceJob.perform_now(voice.id) }
    other=ready_actor;scene=voice.studio_scene.reload
    assert_raises(ArgumentError) { Studio::Director::Finishing.animate!(production:voice.production,actor:@alice,values:{'scene_id'=>scene.id,'cast_asset_id'=>other.id,'voice_operation_id'=>voice.id,'cue_index'=>0,'lock_version'=>scene.lock_version},request_key:SecureRandom.uuid) }
  end
  def test_cast_identity_continuity_rejects_replacing_a_speaker_in_the_next_scene
    result=directed({'dialogue'=>[{'scene'=>1,'speaker'=>'Amina','text'=>'Hello.'},{'scene'=>2,'speaker'=>'Amina','text'=>'Again.'}]})
    production=Production.find(result['production_id']);cast=ready_actor
    result['voice_operations'].each { |row| ScreenplayEngine::AudioSynthesizer.stub(:synthesize!,voice_fixture) { StudioDirectedVoiceJob.perform_now(row['id']) } }
    operations=production.studio_operations.where(capability:'studio.direct.voice').order(:id).to_a
    operations.each_with_index do |op,index|
      selected=index==0 ? cast : ready_actor
      scene=op.studio_scene.reload
      args={production:production,actor:@alice,values:{'scene_id'=>scene.id,'cast_asset_id'=>selected.id,'voice_operation_id'=>op.id,'cue_index'=>0,'lock_version'=>scene.lock_version},request_key:SecureRandom.uuid}
      if index==0
        Studio::Director::Finishing.animate!(**args)
      else
        assert_raises(ArgumentError) { Studio::Director::Finishing.animate!(**args) }
        assert_empty scene.scene_objects.select { |object| object.definition['director_speaker'] }
      end
    end
    assert_equal cast.id,production.reload.metadata.dig('director_cast','Amina','asset_id')
  end
end
