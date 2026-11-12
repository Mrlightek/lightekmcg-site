# frozen_string_literal: true
require_relative "studio_music_checks"
require File.join(ROOT,"app/services/studio/billing/checkout")
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
  def test_production_formats_initialize_actual_edit_without_changing_a_retried_project
    %w[landscape portrait square audio].each do |format|
      key=SecureRandom.uuid
      created=action("project_create",name:"Campaign #{format}",format:format,request_key:key)
      timeline=StudioScene.find(created[:scene_id]).settings.fetch("timeline")
      assert_equal Studio::Editing::Timeline.format(format),timeline.slice("output","width","height","fps")
      assert_equal created,action("project_create",name:"Retry",format:"square",request_key:key)
      assert_equal timeline,StudioScene.find(created[:scene_id]).settings.fetch("timeline")
    end
    assert_raises(ArgumentError){action("project_create",name:"Bad",format:"unknown",request_key:SecureRandom.uuid)}
  end
  def test_production_checkout_returns_to_dashboard_and_legacy_pwa_stays_on_pwa
    operation=@project.studio_operations.create!(studio_scene:@scene,operation_type:"edit_media",provider:"ffmpeg",capability:"studio.workspace.timeline.quote",status:"awaiting_payment",cost_quote:{"total_cents"=>125})
    calls=[]
    Studio::Billing::Checkout.stub(:call,->(**args){calls<<args;{url:"https://checkout.stripe.com/test"}}) do
      result=action("render_checkout",operation_id:operation.id,origin:"https://business.example",scope_site:true)
      assert_equal "https://checkout.stripe.com/test",result[:checkout_url]
      assert_equal "https://business.example/dashboard/studio-broadcasting/workspace/#{@scene.id}?site_id=#{@site.id}#/studio/#{@scene.id}/deliver",calls.last[:success_url]
      assert_equal calls.last[:success_url],calls.last[:cancel_url]
      assert_raises(ActiveRecord::RecordNotFound){action("render_checkout",operation_id:operation.id,site_id:@other_site.id,origin:"https://other.example",scope_site:true)}
      action("render_checkout",operation_id:operation.id,origin:"https://business.example")
      assert_equal "https://business.example/lightek/index.html#/studio/#{@scene.id}",calls.last[:success_url]
      assert_raises(ActiveRecord::RecordNotFound){action("render_checkout",operation_id:operation.id,user_id:@bob.id,site_id:@other_site.id,origin:"https://other.example",scope_site:true)}
    end
  end
  def test_production_export_snapshot_quotes_the_edit_and_survives_further_changes
    asset=recording
    format=Studio::Editing::Timeline.format("portrait")
    action("timeline_save",scene_id:@scene.id,lock_version:@scene.lock_version,timeline:format.merge("clips"=>[{"asset_id"=>asset.id,"out"=>1}]))
    Studio::Billing::Quote.stub(:call,->(operation:,**_){operation.update!(cost_quote:{"total_cents"=>125,"currency"=>"USD"})}) do
      result=action("timeline_quote",scene_id:@scene.id)
      assert_equal "edit_media",result[:operation_type]
      op=StudioOperation.find(result[:operation_id])
      assert_equal 1080,op.manifest.dig("timeline","width")
      assert_equal 1920,op.manifest.dig("timeline","height")
      @scene.reload.update!(settings:@scene.settings.merge("timeline"=>format.merge("clips"=>[])))
      row=action("operations_list",project_id:@project.id)[:operations].find{|r|r[:id]==op.id}
      assert_equal 125,row[:quote]["total_cents"]
      assert_equal 1920,row[:output]["height"]
      assert_equal 1,op.reload.manifest["timeline"]["clips"].size
    end
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
