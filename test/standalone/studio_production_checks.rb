# frozen_string_literal: true
require_relative "studio_music_checks"
class StudioProductionTest < StudioMusicTest
  StudioMusicTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def test_production_new_edit_is_idempotent_scoped_and_needs_no_blender_job
    before=ActiveJob::Base.queue_adapter.enqueued_jobs.size
    key=SecureRandom.uuid
    result=action("project_create",name:"New movie",request_key:key)
    project=StudioProject.find(result[:project_id]);scene=StudioScene.find(result[:scene_id])
    assert_equal @alice.id,project.owner_id
    assert_equal @site.id,project.site_id
    assert_empty scene.scene_objects
    assert_empty scene.settings.fetch("timeline").fetch("clips")
    assert_equal before,ActiveJob::Base.queue_adapter.enqueued_jobs.size
    assert_equal result,action("project_create",name:"New movie",request_key:key)
    assert_raises(ArgumentError){action("project_create",name:"Foreign",request_key:key,site_id:@other_site.id)}
  end
  def test_production_empty_timeline_can_be_saved_but_not_exported
    result=action("timeline_save",scene_id:@scene.id,lock_version:@scene.lock_version,timeline:{"clips"=>[]})
    assert_empty result[:timeline]["clips"]
    assert_equal 0,@scene.reload.settings["timeline"]["duration"]
    assert_raises(ArgumentError){action("timeline_quote",scene_id:@scene.id)}
  end
  def completed_shot(project=@project,draft:false)
    op=project.studio_operations.create!(studio_scene:project.studio_scenes.first,operation_type:"build_scene",provider:"blender",capability:"studio.render.preview",status:"completed",metadata:{"draft_preview"=>draft})
    artifact=op.artifacts.create!(kind:"video",filename:"shot.mp4")
    artifact.file.attach(io:StringIO.new("rendered-shot"),filename:"shot.mp4",content_type:"video/mp4",identify:false)
    artifact
  end
  def handoff(artifact,**values)
    action("artifact_use",scene_id:@scene.id,artifact_id:artifact.id,lock_version:@scene.reload.lock_version,request_key:"render-edit-#{@scene.id}-#{artifact.id}",**values)
  end
  def test_production_handoff_prepares_asset_then_places_once_and_preserves_existing_music
    music=save_score
    action("music_place",scene_id:@scene.id,asset_id:recording.id,revision:music[:revision],lock_version:@scene.reload.lock_version)
    artifact=completed_shot
    waiting=handoff(artifact)
    assert_equal "uploaded",waiting[:status]
    assert_equal 1,@scene.reload.settings["timeline"]["clips"].length
    asset=StudioAsset.find(waiting[:asset_id]);asset.update!(status:"ready",metadata:{"duration"=>2,"has_audio"=>true})
    result=handoff(artifact)
    assert_equal "ready",result[:status]
    assert_equal 2,result[:timeline]["clips"].length
    assert_equal recording.id,result[:timeline]["clips"].first["asset_id"]
    assert_equal asset.id,result[:timeline]["clips"].last["asset_id"]
    assert_equal 1,result[:timeline]["clips"].last["track"] # separate from the score track
    assert_in_delta 0,result[:timeline]["clips"].last["start"],0.01 # music does not push the first picture to its end
    retry_result=handoff(artifact,lock_version:0)
    assert_equal result,retry_result
    assert_equal 2,@scene.reload.settings["timeline"]["clips"].length
    assert_equal 1,StudioAsset.where(request_key:"render-artifact-#{artifact.id}").count
    next_shot=completed_shot
    imported=handoff(next_shot)
    StudioAsset.find(imported[:asset_id]).update!(status:"ready",metadata:{"duration"=>2})
    next_result=handoff(next_shot)
    assert_in_delta 2,next_result[:timeline]["clips"].last["start"],0.01
  end
  def test_production_handoff_rejects_foreign_project_actor_draft_and_stale_edit
    foreign=StudioProject.create!(owner:@bob,site:@other_site,name:"Foreign")
    assert_raises(ActiveRecord::RecordNotFound){handoff(completed_shot(foreign))}
    assert_raises(ArgumentError){handoff(completed_shot(draft:true))}
    artifact=completed_shot
    assert_raises(ActiveRecord::RecordNotFound){handoff(artifact,user_id:@bob.id)}
    result=handoff(artifact)
    StudioAsset.find(result[:asset_id]).update!(status:"ready",metadata:{"duration"=>2})
    @scene.update!(name:"Changed in another editor")
    assert_raises(ArgumentError){handoff(artifact,lock_version:0)}
    assert_nil @scene.reload.settings["timeline"]
    @project.studio_operations.last.update!(status:"failed")
    assert_raises(ActiveRecord::RecordNotFound){handoff(artifact)}
  end
  def test_production_operations_distinguish_draft_previews_from_finished_shots
    completed_shot(draft:true);completed_shot
    helpers=Rails.application.routes.url_helpers
    helpers.define_singleton_method(:rails_blob_path){|*_args,**_options|"/test/private-blob"}
    rows=action("operations_list",project_id:@project.id)[:operations]
    assert_equal [false,true],rows.map{|r|r[:draft_preview]}
    assert rows.all?{|r|r[:scene_id]==@scene.id}
  end
end
