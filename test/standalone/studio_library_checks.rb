# frozen_string_literal: true
require_relative "broadcast_control_checks"
require File.join(ROOT,"app/services/blender/runner")
require File.join(ROOT,"app/services/blender/manifest_builder")
class StudioLibraryTest < BroadcastControlTest
  BroadcastControlTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def setup
    super
    @project=StudioProject.create!(owner:@alice,site:@site,name:"Working library")
    @scene=@project.studio_scenes.first
  end
  def action(name, **payload)
    Studio::Workers::Workspace.perform(name,{user_id:@alice.id,site_id:@site.id}.merge(payload))
  end
  def recipe(key, scene: @scene, **payload)
    action("library_apply",key:key,scene_id:scene.id,lock_version:scene.reload.lock_version,request_key:SecureRandom.hex(16),**payload)
  end
  def test_every_builtin_produces_persisted_scene_objects_media_or_a_targeted_edit
    assert_equal 22,Studio::Library::Catalog.items.length
    Studio::Library::Catalog.items.each do |item|
      scene=@project.studio_scenes.create!(name:item["name"],settings:StudioScene.default_settings)
      target=scene.scene_objects.create!(name:"Target",object_type:"cube",definition:{"location"=>[0,0,1],"rotation"=>[0,0,0],"scale"=>[1,1,1]})
      result=recipe(item["key"],scene:scene,object_id:target.id)
      assert result["object_ids"].any? || result["asset_ids"].any?,item["key"]
      if item["target"]=="object"
        assert target.reload.definition.key?(item["category"]=="materials" ? "material" : "animation"),item["key"]
      else
        result["asset_ids"].each { |id| assert StudioAsset.find(id).file.attached? }
        result["object_ids"].each { |id| assert_includes SceneObject::TYPES,SceneObject.find(id).object_type }
      end
    end
  end
  def test_recipe_retries_are_idempotent_and_stale_mutations_roll_back_scene_objects
    key=SecureRandom.hex(16);version=@scene.lock_version
    payload={key:"char_iris",scene_id:@scene.id,lock_version:version,request_key:key}
    first=action("library_apply",**payload)
    second=action("library_apply",**payload)
    assert_equal first,second
    assert_equal 6,@scene.scene_objects.count
    count=@scene.scene_objects.count
    assert_raises(ArgumentError) { action("library_apply",**payload.merge(request_key:SecureRandom.hex(16))) }
    assert_equal count,@scene.scene_objects.count
  end
  def test_animation_targets_one_library_character_in_a_multi_person_template
    recipe("tpl_single_camera_drama")
    iris=@scene.scene_objects.find_by!(name:"Iris · Head")
    recipe("anim_walk_neutral",object_id:iris.id)
    assert_equal 6,@scene.scene_objects.select { |object| object.name.start_with?("Iris") && object.definition["animation"] }.length
    assert_equal 0,@scene.scene_objects.select { |object| object.name.start_with?("Marcus") && object.definition["animation"] }.length
  end
  def test_library_actions_reject_foreign_scenes_assets_and_unavailable_recipes
    foreign=StudioProject.create!(owner:@bob,site:@other_site,name:"Private")
    @alice.update!(role:"member")
    assert_raises(ActiveRecord::RecordNotFound) { recipe("char_iris",scene:foreign.studio_scenes.first) }
    assert_raises(ArgumentError) { recipe("not_a_recipe") }
    foreign_asset=StudioAsset.create!(owner:@bob,site:@other_site,name:"Private audio",kind:"audio",status:"ready",request_key:SecureRandom.uuid,metadata:{duration:2})
    assert_raises(ActiveRecord::RecordNotFound) { action("asset_use",scene_id:@scene.id,asset_id:foreign_asset.id,lock_version:0,request_key:SecureRandom.hex(16)) }
  end
  def test_generated_media_are_valid_and_export_together_as_a_real_video_master
    recipe("audio_neural_pulse")
    recipe("gfx_lower_thirds",title:"LIGHTEK STUDIO",subtitle:"MARLON HENRY")
    assert_equal %w[audio image],StudioAsset.where(owner:@alice).order(:kind).pluck(:kind)
    StudioAsset.all.each do |asset|
      asset.file.blob.open do |file|
        output,error,status=Open3.capture3("ffprobe","-v","error","-show_streams","-of","json",file.path)
        assert status.success?,error
        stream=JSON.parse(output)["streams"].first
        assert_equal asset.kind=="audio" ? "pcm_s16le" : "png",stream["codec_name"]
        assert_equal 1280,stream["width"] if asset.kind=="image"
      end
    end
    timeline=@scene.reload.settings.fetch("timeline").merge("width"=>160,"height"=>90)
    operation=@project.studio_operations.create!(studio_scene:@scene,operation_type:"edit_media",provider:"ffmpeg",capability:"studio.workspace.timeline.quote",status:"running",intent:{user_id:@alice.id},manifest:{timeline:timeline})
    result=Studio::Providers::FfmpegProvider.new(operation).call
    artifact=Artifact.find(result[:artifact_id])
    assert artifact.file.attached?
    assert_equal "video/mp4",artifact.file.blob.content_type
  end
  def test_media_actions_append_or_layer_with_idempotency_and_real_asset_references
    asset=Studio::Library::GeneratedAsset.call(access:Studio::PwaAccess.new("user_id"=>@alice.id,"site_id"=>@site.id),key:"audio_neural_pulse")
    payload={asset_id:asset.id,scene_id:@scene.id,lock_version:@scene.reload.lock_version,request_key:SecureRandom.hex(16)}
    first=action("asset_use",**payload)
    action("asset_use",**payload)
    assert_equal 1,@scene.reload.settings.dig("timeline","clips").length
    assert_equal asset.id,first["timeline"]["clips"].first["asset_id"]
    action("asset_use",**payload.merge(request_key:SecureRandom.hex(16),lock_version:@scene.lock_version))
    assert_equal 4,@scene.reload.settings.dig("timeline","clips",1,"start")
    action("asset_use",**payload.merge(request_key:SecureRandom.hex(16),lock_version:@scene.lock_version,placement:"overlay"))
    clip=@scene.reload.settings.dig("timeline","clips").last
    assert_equal 0,clip["start"]
    assert_equal 1,clip["track"]
  end
  def test_direct_library_publication_reuses_the_source_and_delivers_through_existing_worker
    asset=Studio::Library::GeneratedAsset.call(access:Studio::PwaAccess.new("user_id"=>@alice.id,"site_id"=>@site.id),key:"audio_neural_pulse")
    key=SecureRandom.hex(16)
    result=action("asset_publish",asset_id:asset.id,scene_id:@scene.id,platform:"lightek_social",request_key:key)
    again=action("asset_publish",asset_id:asset.id,scene_id:@scene.id,platform:"lightek_social",request_key:key)
    assert_equal result[:publication_id],again[:publication_id]
    assert_equal 1,@project.studio_operations.where(operation_type:"asset_source").count
    assert_equal 1,@project.studio_publications.count
    StudioPublicationDispatchJob.perform_now(result[:publication_id])
    publication=StudioPublication.find(result[:publication_id])
    assert_equal "published",publication.status
    assert_equal asset.file.blob.id,Post.find(publication.metadata["post_id"]).media.first.blob.id
    assert_raises(ArgumentError) { action("asset_publish",asset_id:asset.id,scene_id:@scene.id,platform:"octavia",request_key:SecureRandom.hex(16)) }
  end
  def test_library_capabilities_are_exposed_through_the_authenticated_http_boundary
    Api::NevaehController.allow_forgery_protection=false
    client=session_for
    client.post "/api/nevaeh/execute",headers:headers,params:{capability:"studio.workspace.library.apply",payload:{scene_id:@scene.id,key:"prop_phone",lock_version:@scene.lock_version,request_key:SecureRandom.hex(16),user_id:@bob.id,site_id:@other_site.id}},as: :json
    assert_equal 200,client.response.status,client.response.body
    assert_equal 2,@scene.scene_objects.count
    assert_empty SceneObject.where(studio_scene_id:StudioScene.where(studio_project_id:StudioProject.where(site_id:@other_site.id).select(:id)).select(:id))
    client.post "/api/nevaeh/execute",headers:{"Accept"=>"application/json"},params:{capability:"studio.workspace.library.apply",payload:{}},as: :json
    assert_equal 401,client.response.status
  ensure
    Api::NevaehController.allow_forgery_protection=true
  end
  def test_library_pagination_can_reach_older_imports
    101.times { |i| StudioAsset.create!(owner:@alice,site:@site,name:"Media #{i}",kind:"audio",request_key:SecureRandom.uuid) }
    first=action("assets_list")
    assert_equal 100,first[:assets].length
    assert_equal 22,first[:builtins].length
    second=action("assets_list",before:first[:next_before])
    assert_equal 1,second[:assets].length
    assert_nil second[:next_before]
    assert_empty first[:assets].map { |a| a[:id] } & second[:assets].map { |a| a[:id] }
  end
  def test_live_library_selector_contains_only_ready_authorized_media_from_the_current_site
    asset=Studio::Library::GeneratedAsset.call(access:Studio::PwaAccess.new("user_id"=>@alice.id,"site_id"=>@site.id),key:"audio_neural_pulse")
    foreign=Studio::Library::GeneratedAsset.call(access:Studio::PwaAccess.new("user_id"=>@bob.id,"site_id"=>@other_site.id),key:"audio_neural_pulse")
    client=session_for
    Studio::Live::Destination.stub(:configured?,false) { client.get "/dashboard/live?library_asset_id=#{asset.id}",headers:headers.merge("Accept"=>"text/html") }
    assert_equal 200,client.response.status
    assert_includes client.response.body,"/api/lightek/pwa/assets/#{asset.id}/proxy"
    refute_includes client.response.body,"/api/lightek/pwa/assets/#{foreign.id}/proxy"
  end
  def test_real_blender_exports_library_geometry_material_and_animation
    skip "Set LIGHTEK_TEST_BLENDER=1 for native Blender verification" unless ENV["LIGHTEK_TEST_BLENDER"]=="1"
    recipe("char_iris")
    target=@scene.scene_objects.order(:id).first
    recipe("mat_worn_brass",object_id:target.id)
    recipe("anim_walk_neutral",object_id:target.id)
    recipe("cam_intimate_50")
    recipe("light_warm_practical")
    recipe("fx_memory_fragment")
    manifest=Blender::ManifestBuilder.new(@scene.reload).call
    manifest["scene"]["settings"].merge!("render_engine"=>"CYCLES","samples"=>2,"resolution_x"=>128,"resolution_y"=>128)
    Dir.mktmpdir("library-native-") do |dir|
      previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=dir
      op=@project.studio_operations.create!(studio_scene:@scene,operation_type:"build_scene",provider:"blender",capability:"studio.render.preview",status:"running",intent:{user_id:@alice.id},manifest:manifest)
      Rails.stub(:root,Pathname(ROOT)) do
        result=Blender::Runner.new(op).call
        %w[scene.blend scene.glb preview.png].each { |name| assert File.size?(result.output_directory.join(name)),name }
        bytes=File.binread(result.output_directory.join("scene.glb"))
        document=JSON.parse(bytes.byteslice(20,bytes.byteslice(12,4).unpack1("V")))
        assert document.fetch("animations").any?,"GLB should retain library motion"
        check="import bpy,json; obj=bpy.data.objects['Iris · Head']; print('LIBRARY_NATIVE='+json.dumps({'animated':bool(obj.animation_data),'metallic':obj.data.materials[0].node_tree.nodes.get('Principled BSDF').inputs['Metallic'].default_value}))"
        output,error,status=Open3.capture3(ENV.fetch("BLENDER_BIN","blender"),"--background",result.output_directory.join("scene.blend").to_s,"--python-expr",check)
        assert status.success?,error
        data=JSON.parse(output.lines.find { |line| line.start_with?("LIBRARY_NATIVE=") }.split("=",2).last)
        assert data["animated"]
        assert_in_delta 0.85,data["metallic"],0.001
      end
    ensure
      ENV["BLENDER_OUTPUT_ROOT"]=previous
    end
  end
end
