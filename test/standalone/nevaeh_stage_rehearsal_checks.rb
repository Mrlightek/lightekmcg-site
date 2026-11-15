require_relative 'studio_story_pipeline_checks'
%w[app/services/studio/director/rehearsal app/services/nevaeh_os/stage app/models/nevaeh_workspace app/jobs/studio_rehearsal_job db/migrate/20261115233000_create_nevaeh_workspaces].each { |file| require File.join(ROOT,file) }
CreateNevaehWorkspaces.new.migrate(:up)
class NevaehStageRehearsalChecks < StudioStoryPipelineChecks
  def self.runnable_methods = instance_methods(false).grep(/^test_/).map(&:to_s)
  def stage = NevaehOs::Stage.new(@alice)
  def test_stage_persists_work_tabs_scene_and_resource_ownership_with_optimistic_updates
    production=short_episode
    first=stage.read;assert_empty first[:panels]
    saved=stage.update!({'operation'=>'open','lock_version'=>first[:lock_version],'panel'=>{'kind'=>'production','id'=>production.id}})
    assert_equal production.id,saved[:content][:id]
    assert_equal production.studio_scenes.first.id,saved[:content][:scene][:id]
    fresh=NevaehOs::Stage.new(@alice).read;assert_equal saved[:active_key],fresh[:active_key]
    assert_raises(ActiveRecord::StaleObjectError) { stage.update!({'operation'=>'close','lock_version'=>0,'key'=>saved[:active_key]}) }
    other=NevaehOs::Stage.new(@bob)
    assert_raises(ActiveRecord::RecordNotFound) { other.update!({'operation'=>'open','lock_version'=>0,'panel'=>{'kind'=>'production','id'=>production.id}}) }
    assert_raises(ArgumentError) { stage.page!('//evil.example/dashboard/foo') }
    assert_raises(ArgumentError) { stage.page!('/dashboard/nevaeh') }
    assert_equal '/dashboard/servers?site_id=123',stage.page!('/dashboard/servers?site_id=123&token=do-not-store')
    opened=stage.update!({'operation'=>'open','lock_version'=>saved[:lock_version],'panel'=>{'kind'=>'page','path'=>'/dashboard/servers','label'=>'Servers'}})
    assert_equal '/dashboard/servers',opened[:content][:embed_url]
    assert_equal 2,opened[:panels].size
  end
  def test_stage_script_and_contextual_directions_share_the_same_saved_scene
    production=short_episode;scene=production.studio_scenes.first
    value=stage.read;stage.update!({'operation'=>'open','lock_version'=>value[:lock_version],'panel'=>{'kind'=>'production','id'=>production.id}})
    script="AMINA: Let's rehearse together."
    before=scene.lock_version
    stage.save_script!({'production_id'=>production.id,'scene_id'=>scene.id,'lock_version'=>before,'script'=>script})
    assert_equal script,scene.reload.settings.dig('workspace','story','scriptDraft')
    assert_raises(ActiveRecord::StaleObjectError) { stage.save_script!({'production_id'=>production.id,'scene_id'=>scene.id,'lock_version'=>before,'script'=>'Overwrite'}) }
    command=NevaehOs::Command.parse(stage.instruction('rehearse this scene'))
    assert_equal 'rehearse',command['operation'];assert_equal scene.id,command.dig('values','scene_id')
    assert_equal 'susu.list',stage.instruction('susu.list')
  end
  def test_dialogue_sequence_appends_multiple_takes_and_pins_every_recording_without_replacing_cast
    result=directed({'dialogue'=>[{'scene'=>1,'speaker'=>'Amina','text'=>'First line.'},{'scene'=>1,'speaker'=>'Amina','text'=>'Second line.'}]})
    operation=StudioOperation.find(result['voice_operations'].first['id'])
    ScreenplayEngine::AudioSynthesizer.stub(:synthesize!,voice_fixture) { StudioDirectedVoiceJob.perform_now(operation.id) }
    cast=ready_actor;objects=[]
    2.times do |index|
      scene=operation.studio_scene.reload
      value=Studio::Director::Finishing.animate!(production:operation.production,actor:@alice,values:{'scene_id'=>scene.id,'cast_asset_id'=>cast.id,'voice_operation_id'=>operation.id,'cue_index'=>index,'lock_version'=>scene.lock_version},request_key:SecureRandom.uuid)
      objects<<value['object_id']
    end
    assert_equal 1,objects.uniq.size
    object=SceneObject.find(objects.first);takes=object.definition['performance_takes']
    assert_equal 2,takes.size;assert_in_delta 0.8,takes.last['start'],0.03
    manifest=Blender::ManifestBuilder.new(operation.studio_scene.reload).call
    render=operation.studio_scene.studio_operations.create!(studio_project:operation.studio_project,production:operation.production,provider:'blender',operation_type:'build_scene',capability:'studio.render.preview',status:'pending',intent:{'user_id'=>@alice.id},manifest:manifest)
    assert_equal 3,render.performance_sources.count
    assert_equal 2,Studio::Director::Producer.receipt(operation.production,actor:@alice)['performance_takes'].size
  end
  def test_rehearsal_requests_are_owned_idempotent_and_do_not_mutate_the_source_scene
    production=short_episode;scene=production.studio_scenes.first;before=Studio::Director::Finishing.scene_signature(scene)
    key=SecureRandom.uuid;values={'scene_id'=>scene.id,'preview_seconds'=>1}
    first=Studio::Director::Rehearsal.start!(production:production,actor:@alice,values:values,request_key:key)
    again=Studio::Director::Rehearsal.start!(production:production,actor:@alice,values:values,request_key:key)
    assert_equal first,again;assert_equal before,Studio::Director::Finishing.scene_signature(scene.reload)
    assert_raises(ActiveRecord::RecordNotFound) { Studio::Director::Rehearsal.find!(first['rehearsal_id'],actor:@bob) }
    assert_raises(ArgumentError) { Studio::Director::Rehearsal.start!(production:production,actor:@alice,values:values.merge('preview_seconds'=>2),request_key:key) }
    assert_raises(ArgumentError) { Studio::Director::Rehearsal.apply!(operation:StudioOperation.find(first['rehearsal_id']),actor:@alice) }
  end
  def test_rehearsal_apply_checks_ready_report_and_source_revision_then_updates_existing_animation
    production=short_episode;scene=production.studio_scenes.first
    actor=scene.scene_objects.create!(name:'Amina',object_type:'cube',definition:{'blocking_actor'=>true,'location'=>[0,0,1],'animation'=>{'frames'=>[{'frame'=>12,'rotation'=>[0,0,45],'scale'=>[1,1,1]}]}})
    value=Studio::Director::Rehearsal.start!(production:production,actor:@alice,values:{'scene_id'=>scene.id,'preview_seconds'=>1},request_key:SecureRandom.uuid)
    operation=StudioOperation.find(value['rehearsal_id'])
    report={'status'=>'ready','corrections'=>[{'object_id'=>actor.id,'location'=>[-1,0,1],'frames'=>[{'frame'=>1,'location'=>[-1,0,1]},{'frame'=>24,'location'=>[2,0,1]}]}],'unresolved'=>[]}
    operation.update!(status:'completed',metadata:operation.metadata.merge('rehearsal_report'=>report))
    receipt=Studio::Director::Rehearsal.apply!(operation:operation,actor:@alice)
    assert receipt['applied'];assert_equal [-1,0,1],actor.reload.definition['location']
    assert_equal 3,actor.definition.dig('animation','frames').size
    preserved=actor.definition.dig('animation','frames').find { |frame| frame['frame']==12 }
    assert_equal [0,0,45],preserved['rotation'];assert_equal [1,1,1],preserved['scale']
    assert_in_delta 0.4348,preserved['location'][0],0.001
    assert_equal receipt,Studio::Director::Rehearsal.apply!(operation:operation,actor:@alice)
    other=Studio::Director::Rehearsal.start!(production:production,actor:@alice,values:{'scene_id'=>scene.id,'preview_seconds'=>1},request_key:SecureRandom.uuid)
    op=StudioOperation.find(other['rehearsal_id']);op.update!(status:'completed',metadata:op.metadata.merge('rehearsal_report'=>report))
    scene.reload.update!(settings:scene.settings.merge('human_edit'=>true))
    assert_raises(ArgumentError) { Studio::Director::Rehearsal.apply!(operation:op,actor:@alice) }
    assert scene.reload.settings['human_edit']
  end
  def test_real_rehearsal_routes_a_character_around_a_solid_prop_and_keeps_a_playable_preview
    skip 'Set REHEARSAL_REAL_BLENDER=1 to exercise the installed renderer' unless ENV['REHEARSAL_REAL_BLENDER']=='1'
    production=short_episode;scene=production.studio_scenes.first;scene.scene_objects.destroy_all
    actor=scene.scene_objects.create!(name:'Amina',object_type:'cube',definition:{'blocking_actor'=>true,'location'=>[-2,0,1],'scale'=>[0.25,0.25,1]})
    scene.scene_objects.create!(name:'Solid prop',object_type:'cube',definition:{'location'=>[0,0,1],'scale'=>[0.5,0.7,1]})
    scene.scene_objects.create!(name:'Camera',object_type:'camera',definition:{'location'=>[0,-10,7],'look_at'=>[0,0,1],'lens'=>35})
    scene.update!(settings:scene.settings.merge('frame_start'=>1,'frame_end'=>96,'frame_current'=>1,'fps'=>24,'spatial_direction'=>{'personal_space'=>0.9,'collision_detection'=>true}))
    value=Studio::Director::Rehearsal.start!(production:production,actor:@alice,values:{'scene_id'=>scene.id,'goals'=>{actor.id.to_s=>[2,0]},'preview_seconds'=>1},request_key:SecureRandom.uuid)
    Rails.stub(:root,Pathname.new(ROOT)) { StudioRehearsalJob.perform_now(value['rehearsal_id']) }
    operation=StudioOperation.find(value['rehearsal_id']);report=operation.metadata['rehearsal_report']
    assert_equal 'ready',report['status'],report.inspect
    path=report['corrections'].first
    assert path['requires_walk_cycle'];assert path['frames'].any? { |frame| frame['location'][1].abs>1 }
    assert_equal [-2,0,1],actor.reload.definition['location']
    artifact=operation.artifacts.where(kind:'video').first
    artifact.file.blob.open do |file|
      info=JSON.parse(Studio::MediaProcess.run!(['ffprobe','-v','error','-show_entries','format=duration','-of','json',file.path]))
      assert_in_delta 1,Float(info['format']['duration']),0.05
    end
  end
  def test_real_blender_rehearsal_renders_a_private_video_and_reports_geometric_corrections
    skip 'Set REHEARSAL_REAL_BLENDER=1 to exercise the installed renderer' unless ENV['REHEARSAL_REAL_BLENDER']=='1'
    production=short_episode;scene=production.studio_scenes.first
    scene.scene_objects.destroy_all
    scene.scene_objects.create!(name:'Amina',object_type:'cube',definition:{'blocking_actor'=>true,'location'=>[0,0,1],'scale'=>[0.4,0.4,1]})
    scene.scene_objects.create!(name:'Bilal',object_type:'cube',definition:{'blocking_actor'=>true,'location'=>[0.2,0,1],'scale'=>[0.4,0.4,1]})
    scene.scene_objects.create!(name:'Camera',object_type:'camera',definition:{'location'=>[0,-8,5],'look_at'=>[0,0,1],'lens'=>35})
    scene.scene_objects.create!(name:'Light',object_type:'area_light',definition:{'location'=>[0,-3,5],'energy'=>1000,'size'=>5})
    scene.update!(settings:scene.settings.merge('frame_start'=>1,'frame_end'=>4,'frame_current'=>1,'fps'=>24,'spatial_direction'=>{'personal_space'=>0.9,'collision_detection'=>true}))
    original=Studio::Director::Finishing.scene_signature(scene)
    value=Studio::Director::Rehearsal.start!(production:production,actor:@alice,values:{'scene_id'=>scene.id,'preview_seconds'=>1},request_key:SecureRandom.uuid)
    Rails.stub(:root,Pathname.new(ROOT)) { StudioRehearsalJob.perform_now(value['rehearsal_id']) }
    operation=StudioOperation.find(value['rehearsal_id']);assert_equal 'completed',operation.status
    report=operation.metadata['rehearsal_report'];assert_equal 'ready',report['status'],report.inspect
    assert_equal 2,report['corrections'].size
    assert operation.artifacts.where(kind:'video').first.file.attached?
    assert_equal original,Studio::Director::Finishing.scene_signature(scene.reload)
  end
end
