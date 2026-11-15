require_relative 'studio_director_producer_checks'
require File.join(ROOT,'app/services/studio/director/finishing')
require File.join(ROOT,'app/services/studio/director/relationships')
require File.join(ROOT,'app/services/studio/director/personality')
require File.join(ROOT,'app/services/studio/director/story_pipeline')
require File.join(ROOT,'app/services/studio/publishers/social_transport')
require File.join(ROOT,'app/jobs/studio_story_pipeline_job')
require File.join(ROOT,'app/services/studio/performance/motion_plan')
require File.join(ROOT,'app/jobs/studio_episode_assembly_job')
class StudioDirectorFinishingChecks < StudioDirectorProducerChecks
  def self.runnable_methods = instance_methods(false).grep(/^test_/).map(&:to_s)
  def short_episode
    result=directed({'template_key'=>'show_bible/nerd_world_order_series'})
    production=Production.find(result['production_id'])
    production.studio_scenes.each { |scene| scene.update!(settings:scene.settings.merge('frame_start'=>1,'frame_end'=>24,'fps'=>24,'fps_base'=>1)) }
    production
  end
  def scene_exports(production, seconds:1)
    Dir.mktmpdir do |root|
      path=File.join(root,'source.mp4')
      Studio::MediaProcess.run!(['ffmpeg','-v','error','-y','-f','lavfi','-i',"color=c=purple:s=160x90:r=24:d=#{seconds}",'-c:v','libx264','-threads','1','-pix_fmt','yuv420p',path],timeout:30)
      production.studio_scenes.order(:id).map do |scene|
        op=scene.studio_operations.create!(studio_project:production.studio_project,production:production,status:'completed',provider:'ffmpeg',operation_type:'edit_media',capability:'studio.timeline.export',manifest:{'timeline'=>scene.settings['timeline'],'credits'=>['Creator-owned original']})
        artifact=op.artifacts.create!(kind:'video',filename:'scene.mp4')
        File.open(path,'rb') { |file| artifact.file.attach(io:file,filename:'scene.mp4',content_type:'video/mp4',identify:false) }
        artifact.id
      end
    end
  end
  def assemble(production,ids,key:SecureRandom.uuid)
    Studio::Director::Finishing.assemble!(production:production,actor:@alice,values:{'scene_artifact_ids'=>ids},request_key:key)
  end
  def test_finishing_master_has_all_scenes_real_video_and_audio_and_idempotent_replay
    production=short_episode;ids=scene_exports(production);key=SecureRandom.uuid
    result=assemble(production,ids,key:key);op=StudioOperation.find(result['operation_id'])
    StudioEpisodeAssemblyJob.perform_now(op.id)
    assert_equal 'completed',op.reload.status
    assert_in_delta 3,op.manifest['duration'],0.15
    assert_equal ['Creator-owned original'],op.manifest['credits']
    artifact=op.artifacts.find(op.manifest['artifact_id']);assert artifact.file.attached?
    Dir.mktmpdir do |root|
      file=File.join(root,'master.mp4');File.binwrite(file,artifact.file.download)
      info=JSON.parse(Studio::MediaProcess.run!(['ffprobe','-v','error','-show_streams','-of','json',file]))
      assert_equal %w[audio video],info['streams'].map { |stream| stream['codec_type'] }.sort
      assert_equal 1920,info['streams'].find { |stream| stream['codec_type']=='video' }['width']
    end
    assert_equal op.id,assemble(production,ids,key:key)['operation_id']
    StudioEpisodeAssemblyJob.perform_now(op.id);assert_equal 1,op.artifacts.count
    assert_raises(ArgumentError) { assemble(production,ids.reverse,key:key) }
    status=Studio::Director::Producer.receipt(production,actor:@alice)
    assert_equal 'completed',status.dig('director','readiness','episode_master')
    assert status['links'].any? { |link| link['label']=='Review episode master' }
  end
  def test_finishing_rejects_missing_reordered_foreign_draft_or_stale_exports
    production=short_episode;ids=scene_exports(production)
    assert_raises(ArgumentError) { assemble(production,ids.first(2)) }
    assert_raises(ActiveRecord::RecordNotFound) { assemble(production,ids.reverse) }
    source=Artifact.find(ids.first).studio_operation
    source.update!(metadata:{'draft_preview'=>true})
    assert_raises(ArgumentError) { assemble(production,ids) }
    source.update!(metadata:{})
    scene=production.studio_scenes.order(:id).first
    scene.update!(settings:scene.settings.merge('timeline'=>{'changed'=>true}))
    assert_raises(ArgumentError) { assemble(production,ids) }
    assert_empty production.studio_operations.where(capability:'studio.direct.assemble')
    assert_raises(ActiveRecord::RecordNotFound) { Studio::Director::Finishing.assemble!(production:production,actor:@bob,values:{'scene_artifact_ids'=>ids},request_key:SecureRandom.uuid) }
  end
  def test_finishing_cutoff_stale_scene_and_incomplete_runtime_fail_without_master
    production=short_episode;ids=scene_exports(production)
    op=StudioOperation.find(assemble(production,ids)['operation_id'])
    scene=production.studio_scenes.first;scene.update!(settings:scene.settings.merge('creator_edit'=>'Keep me'))
    assert_raises(ArgumentError) { StudioEpisodeAssemblyJob.perform_now(op.id) }
    assert_equal 'failed',op.reload.status;assert_empty op.artifacts
    production=short_episode;ids=scene_exports(production,seconds:0.5)
    op=StudioOperation.find(assemble(production,ids)['operation_id'])
    assert_raises(ArgumentError) { StudioEpisodeAssemblyJob.perform_now(op.id) }
    assert_equal 'failed',op.reload.status;assert_empty op.artifacts
    op.update!(status:'cancelled');StudioEpisodeAssemblyJob.perform_now(op.id);assert_equal 'cancelled',op.reload.status
  end
  def test_finishing_long_episode_is_not_subject_to_single_timeline_limit
    production=Production.find(directed['production_id']);ids=scene_exports(production)
    result=assemble(production,ids);op=StudioOperation.find(result['operation_id'])
    assert_equal 22,op.manifest['sources'].size
    assert_equal 1320,op.manifest['sources'].sum { |source| source['seconds'] }
    assert_equal 'pending',op.status
  end
  def test_finishing_native_delivery_reuses_reviewed_master_and_reports_actual_publisher_outcomes
    production=short_episode;ids=scene_exports(production)
    op=StudioOperation.find(assemble(production,ids)['operation_id']);StudioEpisodeAssemblyJob.perform_now(op.id)
    values={'reviewed'=>true,'artifact_id'=>op.reload.manifest['artifact_id'],'destinations'=>%w[lightek_streaming lightek_social],'title'=>'Episode One'};key=SecureRandom.uuid
    send=->(v=values) { Studio::Director::Finishing.publish!(production:production,actor:@alice,values:v,request_key:key) }
    assert_raises(ArgumentError) { send.call(values.merge('reviewed'=>false)) }
    assert_raises(ArgumentError) { send.call(values.merge('destinations'=>%w[lightek_streaming tiktok])) }
    assert_empty production.studio_publications
    result=send.call;assert_equal 2,result['publication_ids'].size
    assert_equal result,send.call
    assert_raises(ArgumentError) { send.call(values.merge('title'=>'Changed')) }
    result['publication_ids'].each { |id| StudioPublicationDispatchJob.perform_now(id) }
    assert_equal %w[published published],production.studio_publications.order(:id).pluck(:status)
    posts=production.studio_publications.map { |publication| publication.metadata['post_id'] }
    result['publication_ids'].each { |id| StudioPublicationDispatchJob.perform_now(id) }
    assert_equal posts,production.studio_publications.map { |publication| publication.metadata['post_id'] }
    status=Studio::Director::Producer.receipt(production,actor:@alice)
    assert_equal 'published',status.dig('director','readiness','publishing')
  end
  def test_finishing_publication_rechecks_episode_revision_at_dispatch
    production=short_episode;op=StudioOperation.find(assemble(production,scene_exports(production))['operation_id']);StudioEpisodeAssemblyJob.perform_now(op.id)
    result=Studio::Director::Finishing.publish!(production:production,actor:@alice,values:{'reviewed'=>true,'artifact_id'=>op.reload.manifest['artifact_id'],'destinations'=>['lightek_streaming']},request_key:SecureRandom.uuid)
    scene=production.studio_scenes.first;scene.update!(settings:scene.settings.merge('human_change'=>'new revision'))
    assert_raises(ArgumentError) { StudioPublicationDispatchJob.perform_now(result['publication_ids'].first) }
    assert_equal 'failed',StudioPublication.find(result['publication_ids'].first).status
  end
  def test_finishing_animated_cast_uses_voice_audio_real_envelope_gestures_and_preserves_edits
    result=directed({'dialogue'=>[{'scene'=>1,'speaker'=>'Host','text'=>'Welcome.'}]})
    voice=StudioOperation.find(result['voice_operations'].first['id'])
    ScreenplayEngine::AudioSynthesizer.stub(:synthesize!,voice_fixture) { StudioDirectedVoiceJob.perform_now(voice.id) }
    cast=ready_actor;production=voice.production;scene=voice.studio_scene.reload
    values={'scene_id'=>scene.id,'cast_asset_id'=>cast.id,'voice_operation_id'=>voice.id,'cue_index'=>0,'lock_version'=>scene.lock_version};key=SecureRandom.uuid
    perform=->(v=values,k=key) { Studio::Director::Finishing.animate!(production:production,actor:@alice,values:v,request_key:k) }
    result=perform.call;object=SceneObject.find(result['object_id']);take=object.definition['performance']
    assert_operator take['mouth_frames'].size,:>,2
    assert_equal 'nod',take['gestures'].first['kind']
    assert_equal 'Host',object.definition['director_speaker']
    assert_equal result,perform.call
    object.update!(definition:object.definition.merge('creator_edit'=>true))
    assert_raises(ArgumentError) { perform.call(values.merge('lock_version'=>scene.reload.lock_version),SecureRandom.uuid) }
    assert object.reload.definition['creator_edit']
    assert_equal 1,scene.scene_objects.count { |item| item.definition['director_speaker']=='Host' }
  end
  def test_finishing_render_quotes_reuse_current_scenes_and_require_existing_payment_flow
    production=short_episode;key=SecureRandom.uuid
    quote=->(operation:,**_) { operation.update!(cost_quote:{'total_cents'=>125,'currency'=>'USD'}) }
    result=nil
    Studio::Billing::Quote.stub(:call,quote) do
      result=Studio::Director::Finishing.render!(production:production,actor:@alice,request_key:key)
      again=Studio::Director::Finishing.render!(production:production,actor:@alice,request_key:key)
      assert_equal result,again
    end
    assert_equal 3,result['render_operations'].size
    result['render_operations'].each do |row|
      op=StudioOperation.find(row['id']);assert_equal 'awaiting_payment',op.status
      assert op.manifest.dig('outputs','animation');refute op.metadata['draft_preview']
      assert_equal 125,row.dig('quote','total_cents')
    end
    scene=production.studio_scenes.first;scene.update!(settings:scene.settings.merge('creator_edit'=>true))
    assert_raises(ArgumentError) { Studio::Director::Finishing.render!(production:production,actor:@alice,request_key:key) }
  end
  def test_finishing_automatic_source_selection_requires_every_current_scene
    production=short_episode
    assert_raises(ArgumentError) { Studio::Director::Finishing.assemble!(production:production,actor:@alice,values:{},request_key:SecureRandom.uuid) }
    ids=scene_exports(production)
    receipt=Studio::Director::Finishing.assemble!(production:production,actor:@alice,values:{},request_key:SecureRandom.uuid)
    assert_equal ids,StudioOperation.find(receipt['operation_id']).manifest['sources'].map { |row| row['artifact_id'] }
    command=NevaehOs::Command.parse("/produce assemble #{production.id}")
    assert_equal({},command['values']);assert_equal 'assemble',command['operation']
  end
  def test_finishing_commands_are_owned_and_preview_mode_does_not_assemble
    result=NevaehOs::Command.parse('/produce assemble {"production_id":12,"scene_artifact_ids":[1,2]}')
    assert_equal 'assemble',result['operation'];assert_equal 12,result['id']
    assert_equal [1,2],result['values']['scene_artifact_ids']
    assert_raises(ArgumentError) { NevaehOs::Command.parse('/produce publish {"reviewed":true}') }
    production=short_episode;ids=scene_exports(production)
    conversation=NevaehOs::Conversation.new(actor:@alice,host:@site.host)
    response=conversation.ask(text:"/produce assemble #{ {'production_id'=>production.id,'scene_artifact_ids'=>ids}.to_json }",request_key:SecureRandom.uuid,mode:'decide')
    assert_equal 'planned',response['status']
    assert_empty production.studio_operations.where(capability:'studio.direct.assemble')
  end
end
