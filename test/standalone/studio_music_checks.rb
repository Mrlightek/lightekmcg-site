# frozen_string_literal: true
require_relative "studio_performance_checks"
require File.join(ROOT,"app/services/studio/music/composition")
require File.join(ROOT,"app/services/studio/music/patterns")
require File.join(ROOT,"app/services/studio/music/automation")
require File.join(ROOT,"app/services/studio/assets/upload")
require File.join(ROOT,"app/services/studio/workers/pwa")
# Standalone checks substitute only the external gem's query adapter, with real AR relations.
module DymondStudio
  class StudioV2Domain
    def productions(project:) = project.productions.to_a
    def scenes(project:) = project.studio_scenes.to_a
  end
end
Rails.application.routes.draw do
  post "/dashboard/studio-broadcasting/execute",to:"dashboard/media_studio#workspace_execute"
  post "/dashboard/studio-broadcasting/uploads",to:"dashboard/media_studio#workspace_upload"
  get "/dashboard/studio-broadcasting/assets/:id/:flavor",to:"dashboard/media_studio#workspace_asset"
end
class StudioMusicTest < StudioPerformanceTest
  StudioPerformanceTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def score
    {version:1,name:"My score",tempo:100,bars:4,swing:0.2,tracks:[{id:"kick",name:"Kick",instrument:"kick",notes:[{beat:0,length:0.125,pitch:60,velocity:0.9}]},{id:"bass",name:"Bass",instrument:"bass",pan:-0.3,gain:0.6,notes:[{beat:0,length:1,pitch:36,velocity:0.7}]}]}
  end
  def save_score(data=score,**args)
    action("music_save",scene_id:@scene.id,lock_version:@scene.reload.lock_version,composition:data,**args)
  end
  def test_music_save_preserves_source_and_template_episodes_have_independent_notes
    before=@scene.settings.deep_dup
    result=save_score
    assert_equal 1,result[:revision]
    assert_equal "My score",@scene.reload.settings.dig("music","name")
    assert_equal before["resolution_x"],@scene.settings["resolution_x"]
    template=action("template_save",project_id:@project.id,name:"Series",request_key:SecureRandom.uuid)
    episode=action("template_use",project_id:template[:project_id],name:"Episode 2",request_key:SecureRandom.uuid)
    copy=StudioScene.find(episode[:scene_id])
    assert_equal @scene.settings["music"],copy.settings["music"]
    changed=score;changed[:tracks][0][:notes][0][:beat]=1
    save_score(changed,scene_id:copy.id,lock_version:copy.lock_version)
    assert_equal 0,@scene.reload.settings.dig("music","tracks",0,"notes",0,"beat")
    assert_equal 1,copy.reload.settings.dig("music","tracks",0,"notes",0,"beat")
  end
  def test_music_rejects_invalid_song_bounds_duplicate_notes_and_stale_writes
    save_score
    original=@scene.reload.settings["music"]
    [{tempo:0},{bars:129},{bars:128,tempo:40},{swing:0.6},{version:8},{bars:4.1}].each do |changes|
      assert_raises(ArgumentError) { save_score(score.merge(changes)) }
    end
    invalid=score;invalid[:tracks][0][:notes]<<invalid[:tracks][0][:notes].first.dup
    assert_raises(ArgumentError) { save_score(invalid) }
    invalid=score;invalid[:tracks][0][:notes][0][:beat]=16
    assert_raises(ArgumentError) { save_score(invalid) }
    assert_raises(ArgumentError) { save_score(score,lock_version:0) }
    assert_equal original,@scene.reload.settings["music"]
  end
  def test_music_bounces_replace_linked_audio_without_stacking_or_losing_editor_work
    saved=save_score
    first=action("music_place",scene_id:@scene.id,asset_id:recording.id,revision:saved[:revision],lock_version:@scene.reload.lock_version)
    assert_equal 1,first[:timeline]["clips"].length
    retry_result=action("music_place",scene_id:@scene.id,asset_id:recording.id,revision:saved[:revision],lock_version:0)
    assert_equal first,retry_result
    edit=@scene.reload.settings["timeline"].deep_dup
    edit["clips"][0].merge!("start"=>4,"gain"=>0.4,"out"=>0.5)
    action("timeline_save",scene_id:@scene.id,lock_version:@scene.lock_version,timeline:edit)
    new_asset=StudioAsset.new(owner:@alice,site:@site,name:"Revised music",kind:"audio",status:"ready",request_key:SecureRandom.uuid,metadata:recording.metadata)
    new_asset.file.attach(recording.file.blob);new_asset.save!
    saved=save_score
    assert_raises(ArgumentError) { action("music_place",scene_id:@scene.id,asset_id:new_asset.id,revision:saved[:revision]-1,lock_version:@scene.reload.lock_version) }
    revised=action("music_place",scene_id:@scene.id,asset_id:new_asset.id,revision:saved[:revision],lock_version:@scene.reload.lock_version)
    clip=revised[:timeline]["clips"].sole
    assert_equal new_asset.id,clip["asset_id"]
    assert_equal 4,clip["start"]
    assert_equal 0.4,clip["gain"]
    assert_equal 0.5,clip["out"]
    assert_equal recording.id,first[:timeline]["clips"][0]["asset_id"]
  end
  def test_music_validates_sampler_slice_and_account_access
    a=recording
    data=score;data[:tracks]<<{id:"sample",instrument:"sample",asset_id:a.id,sample_in:0.2,sample_out:0.8,root:60,notes:[{beat:1,length:0.5,pitch:64,velocity:0.7}]}
    save_score(data)
    assert_equal a.id,@scene.reload.settings.dig("music","tracks",2,"asset_id")
    assert_raises(ArgumentError) { save_score(data.deep_dup.tap { |s|s[:tracks][2][:sample_out]=3 }) }
    @alice.update!(role:"member");a.update!(owner:@bob,site:@other_site)
    assert_raises(ActiveRecord::RecordNotFound) { save_score(data) }
  end
  def test_music_dashboard_transport_forces_selected_site_and_actor_and_rejects_foreign_scene
    foreign=StudioProject.create!(owner:@bob,site:@other_site,name:"Other project").studio_scenes.first
    client=session_for
    request={capability:"studio.workspace.music.save",payload:{scene_id:@scene.id,lock_version:0,composition:score,user_id:@bob.id,site_id:@other_site.id}}
    client.post "/dashboard/studio-broadcasting/execute?site_id=#{@site.id}",headers:headers,params:request,as: :json
    assert_equal 200,client.response.status,client.response.body
    assert_equal "completed",body(client)["status"]
    assert @scene.reload.settings["music"]
    client.post "/dashboard/studio-broadcasting/execute?site_id=#{@site.id}",headers:headers,params:request.deep_merge(payload:{scene_id:foreign.id}),as: :json
    assert_equal 404,client.response.status
    client.post "/dashboard/studio-broadcasting/execute?site_id=#{@site.id}",headers:headers,params:{capability:"execute.ruby",payload:{}},as: :json
    assert_equal 422,client.response.status
    client.post "/dashboard/studio-broadcasting/execute?site_id=#{@site.id}",headers:headers,params:{capability:"studio.workspace.music.save",payload:"invalid"},as: :json
    assert_equal 422,client.response.status
    client.post "/dashboard/studio-broadcasting/execute?site_id=#{@site.id}",headers:headers,params:request.merge(payload:request[:payload].merge(composition:{})),as: :json
    assert_equal 422,client.response.status
    client.post "/dashboard/studio-broadcasting/execute?site_id=#{@site.id}",headers:headers,params:{capability:"studio.pwa.bootstrap",payload:{}},as: :json
    assert_equal 200,client.response.status,client.response.body
    assert_equal [@project.id],body(client).dig("result","projects").map { |p|p["id"] }
  end
  def test_music_native_upload_asset_access_and_csrf_are_enforced
    client=session_for
    file=Tempfile.new(["music", ".wav"])
    bytes="RIFF"+[38].pack("V")+"WAVEfmt "+[16,1,1,8000,16000,2,16].pack("VvvVVvv")+"data"+[2,0].pack("Vs")
    file.binmode;file.write(bytes);file.flush
    upload=Rack::Test::UploadedFile.new(file.path,"audio/wav")
    client.post "/dashboard/studio-broadcasting/uploads?site_id=#{@site.id}",headers:headers,params:{file:upload}
    assert_equal 201,client.response.status,client.response.body
    blob=ActiveStorage::Blob.find_signed!(body(client)["signed_id"])
    assert_equal @site.id,blob.metadata["lightek_site_id"]
    assert_equal @alice.id,blob.metadata["lightek_user_id"]
    foreign=StudioAsset.create!(owner:@bob,site:@other_site,name:"Private",kind:"audio",request_key:SecureRandom.uuid)
    foreign.file.attach(blob)
    client.get "/dashboard/studio-broadcasting/assets/#{foreign.id}/original?site_id=#{@site.id}",headers:headers
    assert_equal 404,client.response.status
    Dashboard::MediaStudioController.allow_forgery_protection=true
    client.post "/dashboard/studio-broadcasting/execute?site_id=#{@site.id}",headers:headers,params:{capability:"studio.pwa.bootstrap",payload:{}},as: :json
    assert_equal 422,client.response.status
  ensure
    Dashboard::MediaStudioController.allow_forgery_protection=false
    file&.close!
  end
end
