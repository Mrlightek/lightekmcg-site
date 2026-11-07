# frozen_string_literal: true
require_relative "native_blender_checks"
class StudioCreationTest < NativeBlenderTest
  NativeBlenderTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def create_asset(**payload)
    action("blender_create",**{recipe:"cube",name:"My prop",size:2,color:"#ff0000",roughness:0.3,metallic:0.8,request_key:SecureRandom.uuid}.merge(payload))
  end
  def test_creation_builds_editable_geometry_camera_and_lighting_without_provider
    result=create_asset
    scene=StudioScene.find(result["scene_id"])
    cube=scene.scene_objects.find(result["object_id"])
    assert_equal [2,2,2],cube.definition["scale"]
    assert_equal [1,0,0,1],cube.definition.dig("material","color")
    assert_equal 0.8,cube.definition.dig("material","metallic")
    assert scene.scene_objects.exists?(object_type:"camera")
    assert scene.scene_objects.exists?(object_type:"area_light")
    assert_equal 10,action("assets_list")[:creation_recipes].length
  end
  def test_creation_requests_are_idempotent_and_stale_edits_roll_back
    key=SecureRandom.uuid
    first=create_asset(request_key:key)
    again=create_asset(request_key:key)
    assert_equal first["scene_id"],again["scene_id"]
    payload={scene_id:@scene.id,lock_version:@scene.lock_version,request_key:SecureRandom.uuid}
    initial=create_asset(**payload)
    assert_equal initial,create_asset(**payload).except("lock_version").merge("lock_version"=>initial["lock_version"])
    assert_equal 1,@scene.scene_objects.count
    assert_raises(ArgumentError) { create_asset(**payload.merge(request_key:SecureRandom.uuid)) }
    assert_equal 1,@scene.scene_objects.count
  end
  def test_creation_rejects_foreign_scenes_bad_recipes_and_unbounded_values
    @alice.update!(role:"member")
    foreign=StudioProject.create!(owner:@bob,site:@other_site,name:"Private")
    assert_raises(ActiveRecord::RecordNotFound) { create_asset(scene_id:foreign.studio_scenes.first.id,lock_version:0) }
    [{recipe:"python"},{size:Float::INFINITY},{size:0},{roughness:2},{metallic:-1},{color:"red"}].each do |values|
      assert_raises(ArgumentError) { create_asset(**values) }
    end
    assert_equal 0,@scene.scene_objects.count
  end
  def test_creation_every_recipe_produces_objects_and_scaled_effect_keyframes
    Studio::NativeBlender::Create.items.each do |item|
      result=create_asset(recipe:item[:key])
      assert result["object_ids"].any?,item[:key]
      scene=StudioScene.find(result["scene_id"])
      assert scene.scene_objects.all? { |object| SceneObject::TYPES.include?(object.object_type) }
      if item[:key]=="fx_memory_fragment"
        object=scene.scene_objects.find(result["object_id"])
        assert_equal object.definition["location"],object.definition.dig("animation","frames",0,"location")
      end
    end
  end
  def test_saved_source_export_is_a_snapshot_and_is_idempotent
    result=create_asset
    scene=StudioScene.find(result["scene_id"])
    payload={scene_id:scene.id,lock_version:scene.lock_version,request_key:SecureRandom.uuid}
    saved=action("blender_asset_save",**payload)
    again=action("blender_asset_save",**payload)
    assert_equal saved[:asset_id],again[:asset_id]
    op=StudioOperation.find(saved[:operation_id])
    assert_equal({"blend"=>true,"bundle"=>false},op.manifest["outputs"])
    scene.scene_objects.first.update!(name:"Changed after save")
    refute_equal "Changed after save",op.reload.manifest.dig("scene","objects",0,"name")
    assert_raises(ArgumentError) { action("blender_asset_save",**payload.merge(lock_version:999,request_key:SecureRandom.uuid)) }
    assert_equal 1,scene.studio_operations.count
  end
  def test_saved_source_job_failure_can_retry_before_a_file_exists
    result=create_asset
    scene=StudioScene.find(result["scene_id"])
    saved=action("blender_asset_save",scene_id:scene.id,lock_version:scene.lock_version,request_key:SecureRandom.uuid)
    Studio::Providers::BlenderProvider.stub(:new,->(_op){raise "Blender missing"}) do
      assert_raises(RuntimeError) { StudioAssetSaveJob.perform_now(saved[:operation_id]) }
    end
    asset=StudioAsset.find(saved[:asset_id]);assert_equal "failed",asset.status
    assert_equal "Blender missing",asset.error_message
    action("asset_retry",asset_id:asset.id)
    assert_equal "pending",StudioOperation.find(saved[:operation_id]).status
    assert_equal "processing",asset.reload.status
  end
  def test_creation_runtime_health_starts_blender_inside_the_restricted_worker
    Rails.stub(:env,ActiveSupport::StringInquirer.new("production")) do
      command=nil
      Studio::MediaProcess.stub(:run!,->(args,**_opts){command=args; "LIGHTEK_BLENDER_RUNTIME_READY=4.0.2\n"}) do
        health=action("blender_runtime_status")
        assert health[:ready]
        assert_equal "4.0.2",health[:version]
        assert_includes command,"--disable-autoexec"
        assert_equal "none",command[command.index("--network")+1]
        refute_includes command,"-v"
      end
      Studio::MediaProcess.stub(:run!,->(*_args,**_opts){"Image exists but Blender never started"}) do
        refute action("blender_runtime_status")[:ready]
      end
    end
  end
  def test_creation_real_blender_save_and_reopen_native_asset
    skip "Set LIGHTEK_TEST_BLENDER=1" unless ENV["LIGHTEK_TEST_BLENDER"]=="1"
    Dir.mktmpdir("studio-create-") do |root|
      previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=root
      result=create_asset(recipe:"fx_memory_fragment")
      scene=StudioScene.find(result["scene_id"])
      saved=action("blender_asset_save",scene_id:scene.id,lock_version:scene.lock_version,request_key:SecureRandom.uuid)
      Rails.stub(:root,Pathname(ROOT)) { StudioAssetSaveJob.perform_now(saved[:operation_id]) }
      asset=StudioAsset.find(saved[:asset_id])
      assert_equal "ready",asset.status
      assert asset.native.attached?
      assert asset.proxy.attached?,asset.metadata["warnings"].inspect
      assert_equal "glTF",asset.proxy.blob.download.byteslice(0,4)
      reopened=action("blender_template_use",asset_id:asset.id,request_key:SecureRandom.uuid)
      native=StudioScene.find(reopened[:scene_id])
      assert_equal 8,native.scene_objects.where(object_type:"native_object").count { |o| o.definition["native_type"]=="MESH" }
      assert native.blender_source.attached?
      assert_equal "completed",StudioOperation.find(saved[:operation_id]).status
    ensure
      ENV["BLENDER_OUTPUT_ROOT"]=previous
    end
  end
end
