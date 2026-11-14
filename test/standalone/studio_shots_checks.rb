# frozen_string_literal: true
require_relative "studio_production_checks"
require File.join(ROOT,"app/services/studio/shots/board")
require File.join(ROOT,"app/services/studio/ai/runtime")
require File.join(ROOT,"app/services/studio/ai/generation")
require File.join(ROOT,"app/jobs/studio_ai_generation_job")

class StudioShotsTest < StudioProductionTest
  StudioProductionTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def setup
    super
    # The isolated host omits the private application's ActiveStorage routes.
    Rails.application.routes.url_helpers.define_singleton_method(:rails_blob_path) { |*_args,**_options| "/test/private-blob" }
  end

  def shot_camera
    @shot_camera ||= @scene.scene_objects.create!(name:"Wide camera",object_type:"camera",definition:{location:[4,-6,3],look_at:[0,0,0],lens:35})
  end
  def shot(**values)
    {id:SecureRandom.uuid,name:"Opening wide",camera_id:shot_camera.id,frame_start:1,frame_end:24,cast_ids:[],notes:"Hold the wide shot",prompt:"A warmly lit studio"}.merge(values)
  end
  def save_board(shots,**values)
    action("shots_save",scene_id:@scene.id,lock_version:@scene.reload.lock_version,shots:shots,request_key:SecureRandom.uuid,**values)
  end
  def list_board = action("shots_list",scene_id:@scene.id)
  def quote_shot(row,**values)
    action("render_quote",scene_id:@scene.id,shot_id:row[:id],output:"movie",lock_version:@scene.reload.lock_version,request_key:SecureRandom.uuid,**values)
  end

  def test_shots_order_sources_and_idempotent_saves_survive_reopening
    first=shot;second=shot(name:"Close up",frame_start:25,frame_end:48)
    payload={request_key:SecureRandom.uuid,lock_version:@scene.lock_version}
    result=save_board([second,first],**payload)
    assert_equal result,save_board([second,first],**payload)
    assert_equal [second[:id],first[:id]],list_board[:shots].map { |s| s["id"] }
    assert_equal 1,@scene.reload.settings.dig("shot_board","revision")
    assert_raises(ArgumentError) { save_board([first],**payload) }
    assert_equal 2,@scene.settings.dig("shot_board","shots").length
  end

  def test_shots_reject_foreign_references_invalid_frames_and_oversized_boards
    first=shot
    [first.merge(camera_id:999999),first.merge(frame_start:2,frame_end:1),first.merge(frame_end:2401),first.merge(frame_start:1.5),first.merge(cast_ids:[shot_camera.id]),first.merge(prompt:"x"*2001)].each do |bad|
      assert_raises(ArgumentError) { save_board([bad]) }
    end
    assert_raises(ArgumentError) { save_board([first,first]) }
    assert_raises(ArgumentError) { save_board(Array.new(65) { shot }) }
    assert_raises(ArgumentError) { save_board(["invalid"]) }
    @alice.update!(role:"member")
    foreign=StudioProject.create!(owner:@bob,site:@other_site,name:"Private").studio_scenes.first
    assert_raises(ActiveRecord::RecordNotFound) { action("shots_list",scene_id:foreign.id) }
    assert_raises(ActiveRecord::RecordNotFound) { save_board([first],scene_id:foreign.id) }
    assert_nil @scene.reload.settings["shot_board"]
  end

  def test_shots_rebase_unrelated_edits_but_do_not_overwrite_a_newer_board
    row=shot;save_board([row]);original_lock=@scene.reload.lock_version
    @scene.update!(settings:@scene.settings.merge("workspace"=>{"story"=>{"script"=>"Keep this script"}}))
    save_board([row.merge(notes:"Revised direction")],lock_version:original_lock,board_revision:1)
    assert_equal "Keep this script",@scene.reload.settings.dig("workspace","story","script")
    assert_equal "Revised direction",@scene.settings.dig("shot_board","shots",0,"notes")
    assert_raises(ArgumentError) { save_board([row],lock_version:original_lock,board_revision:1) }
    assert_equal "Revised direction",@scene.reload.settings.dig("shot_board","shots",0,"notes")
  end

  def test_shots_quote_freezes_camera_cast_frames_without_changing_the_scene
    actor=placed_actor
    other=placed_actor
    row=shot(cast_ids:[actor.id],frame_start:3,frame_end:10);save_board([row])
    before=@scene.reload.settings.deep_dup
    Studio::Billing::Quote.stub(:call,->(operation:,**_){operation.update!(cost_quote:{"total_cents"=>125})}) do
      result=quote_shot(row)
      operation=StudioOperation.find(result[:operation_id]);settings=operation.manifest.dig("scene","settings")
      assert_equal 3,settings["frame_start"];assert_equal 10,settings["frame_end"]
      assert_equal shot_camera.id,settings["active_camera_object_id"]
      assert operation.manifest.dig("outputs","animation")
      refute_includes operation.manifest["scene"]["objects"].map { |o|o["id"] },other.id
      assert_equal before,@scene.reload.settings
      save_board([row.merge(frame_end:12)])
      assert_equal 10,operation.reload.manifest.dig("scene","settings","frame_end")
      assert list_board[:shots].first.dig("render","stale")
    end
  end

  def test_shots_quote_retries_recover_pricing_without_duplicate_operations
    row=shot;save_board([row]);key=SecureRandom.uuid
    Studio::Billing::Quote.stub(:call,->(**_){raise ArgumentError,"Pricing unavailable"}) do
      assert_raises(ArgumentError) { quote_shot(row,request_key:key) }
    end
    assert_equal 1,@scene.studio_operations.count
    Studio::Billing::Quote.stub(:call,->(operation:,**_){operation.update!(cost_quote:{"total_cents"=>125})}) do
      result=quote_shot(row,request_key:key)
      assert_equal result,quote_shot(row,request_key:key,lock_version:0)
      assert_equal 1,@scene.studio_operations.count
      shot_camera.update!(definition:shot_camera.definition.merge("lens"=>50))
      assert_raises(ArgumentError) { quote_shot(row,request_key:key) }
      assert list_board[:shots].first.dig("render","stale")
    end
  end

  def test_shots_templates_remap_camera_and_cast_and_drop_receipts
    actor=placed_actor;row=shot(cast_ids:[actor.id]);save_board([row])
    saved=action("template_save",project_id:@project.id,name:"Show",request_key:SecureRandom.uuid)
    episode=action("template_use",project_id:saved[:project_id],name:"Episode 2",request_key:SecureRandom.uuid)
    copy=StudioScene.find(episode[:scene_id]);copied=copy.settings.dig("shot_board","shots",0)
    refute_equal shot_camera.id,copied["camera_id"]
    assert_equal "camera",copy.scene_objects.find(copied["camera_id"]).object_type
    refute_equal actor.id,copied["cast_ids"].first
    assert copy.scene_objects.find(copied["cast_ids"].first).definition["character_profile"]
    refute copy.settings.key?("shot_board_receipts")
    assert_empty action("shots_list",scene_id:copy.id)[:shots].first.fetch("render") || []
  end

  def test_shots_completed_artifacts_hand_back_to_the_edit_with_the_shot_name
    row=shot;save_board([row])
    Studio::Billing::Quote.stub(:call,->(operation:,**_){operation.update!(cost_quote:{"total_cents"=>125})}) do
      result=quote_shot(row);operation=StudioOperation.find(result[:operation_id]);operation.update!(status:"completed")
      artifact=operation.artifacts.create!(kind:"video",filename:"movie.mp4")
      artifact.file.attach(io:StringIO.new("rendered"),filename:"movie.mp4",content_type:"video/mp4",identify:false)
      board=list_board[:shots].first
      refute board.dig("render","stale");assert_equal artifact.id,board.dig("render","artifacts",0,"id")
      waiting=handoff(artifact);asset=StudioAsset.find(waiting[:asset_id]);assert_equal row[:name],asset.name
      asset.update!(status:"ready",metadata:{"duration"=>1,"has_audio"=>true})
      ready=handoff(artifact);assert_equal asset.id,ready[:timeline]["clips"].first["asset_id"]
      assert_equal ready,handoff(artifact)
      assert_equal ready,handoff(artifact,shot_id:row[:id])
      shot_camera.update!(definition:shot_camera.definition.merge("lens"=>55))
      assert_raises(ArgumentError) { handoff(artifact,shot_id:row[:id]) }
      shot_camera.update!(definition:shot_camera.definition.merge("native_deleted"=>true))
      assert_match(/camera/,list_board[:shots].first["validation_error"])
    end
  end

  def test_shots_real_render_uses_selected_camera_and_frame_range
    skip "Set LIGHTEK_TEST_BLENDER=1" unless ENV["LIGHTEK_TEST_BLENDER"]=="1"
    @scene.scene_objects.create!(name:"Prop",object_type:"cube",definition:{location:[0,0,0],scale:[1,1,1]})
    @scene.update!(settings:@scene.settings.merge("render_engine"=>"CYCLES","samples"=>1,"resolution_x"=>64,"resolution_y"=>64))
    row=shot(frame_start:3,frame_end:4);save_board([row])
    Studio::Billing::Quote.stub(:call,->(**_){}) do
      result=quote_shot(row);operation=StudioOperation.find(result[:operation_id]);operation.update!(status:"running")
      Dir.mktmpdir("shot-render-") do |root|
        previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=root
        rendered=Rails.stub(:root,Pathname(ROOT)) { Studio::Providers::BlenderProvider.new(operation).call }
        check="import bpy; s=bpy.context.scene; assert s.camera.name=='Wide camera'; assert s.frame_start==3 and s.frame_end==4; print('SHOT_CAMERA_RANGE_PASS')"
        output=Studio::MediaProcess.run!([ENV.fetch("BLENDER_BIN","blender"),"--background",rendered.output_directory.join("scene.blend").to_s,"--disable-autoexec","--python-exit-code","1","--python-expr",check],timeout:60)
        assert_includes output,"SHOT_CAMERA_RANGE_PASS"
        data=JSON.parse(Studio::MediaProcess.run!(["ffprobe","-v","error","-show_streams","-of","json",rendered.output_directory.join("movie.mp4").to_s],timeout:10))
        assert_equal "2",data["streams"].first["nb_frames"]
      ensure
        ENV["BLENDER_OUTPUT_ROOT"]=previous
      end
    end
  end

  def test_shots_generation_keeps_the_saved_shot_identity_in_its_asset
    row=shot;save_board([row])
    runtime=Object.new
    runtime.define_singleton_method(:inventory) { {recipes:[{id:"image",ready:true,kind:"image"}],models:["local"]} }
    runtime.define_singleton_method(:graph) { |*_args,**_kwargs| [{},{"1"=>{"class_type"=>"Fixture","inputs"=>{}}}] }
    Studio::Ai::Runtime.stub(:new,runtime) do
      result=action("ai_generate",scene_id:@scene.id,shot_id:row[:id],prompt:row[:prompt],seed:42,recipe:"image",model:"local",request_key:SecureRandom.uuid)
      assert_equal row[:id],result[:shot_id]
      assert_equal row[:name],StudioAsset.find(result[:asset_id]).metadata.dig("ai_intent","shot_name")
      assert_raises(ArgumentError) { action("ai_generate",scene_id:@scene.id,shot_id:"foreign-shot",prompt:"Concept",seed:42,recipe:"image",model:"local",request_key:SecureRandom.uuid) }
    end
  end

  def test_shots_dashboard_transport_pins_the_actor_and_application
    row=shot;client=session_for
    payload={scene_id:@scene.id,lock_version:@scene.lock_version,shots:[row],request_key:SecureRandom.uuid,user_id:@bob.id,site_id:@other_site.id}
    client.post "/dashboard/studio-broadcasting/execute?site_id=#{@site.id}",headers:headers,params:{capability:"studio.workspace.shots.save",payload:payload},as: :json
    assert_equal 200,client.response.status,client.response.body
    assert_equal row[:name],@scene.reload.settings.dig("shot_board","shots",0,"name")
    foreign=StudioProject.create!(owner:@bob,site:@other_site,name:"Private").studio_scenes.first
    client.post "/dashboard/studio-broadcasting/execute?site_id=#{@site.id}",headers:headers,params:{capability:"studio.workspace.shots.list",payload:{scene_id:foreign.id}},as: :json
    assert_equal 404,client.response.status
  end
end
