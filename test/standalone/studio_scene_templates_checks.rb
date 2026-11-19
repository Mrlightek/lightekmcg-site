require_relative "studio_character_scene_checks"
class StudioSceneTemplatesTest < StudioCharacterSceneTest
  StudioCharacterSceneTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def catalog = action("character_scene_catalog",scene_id:@scene.id)
  def launch(**values)
    action("character_template_use",scene_id:@scene.id,source:"production",name:"Original pilot",template_key:"production/network_procedural_42",request_key:"template-launch-test",**values)
  end
  def test_catalog_and_production_launch_use_the_actual_registered_templates
    first=catalog
    assert first[:scene_templates].any? { |row| row[:key]=="library:tpl_night_exterior" }
    expected=Studio::NativeBlender::MediaPresets.items.select { |row| row["project_template"] && !row["requires_asset"] }.map { |row| row["key"] }
    assert_equal expected,first[:production_templates].map { |row| row["key"] }
    assert first[:production_templates].any? { |row| row["key"]=="production/network_procedural_42" }
    result=launch
    assert_equal result,launch
    project=StudioProject.find(result["project_id"])
    assert_equal "Original pilot",project.name
    assert_equal "staged",result["status"]
    assert_equal result["scenes"].length,project.studio_scenes.count
    assert_operator project.studio_scenes.count,:>,1
    assert project.studio_scenes.any? { |scene| scene.scene_objects.where(object_type:"camera").exists? }
    assert_raises(ArgumentError) { launch(name:"Different project") }
    assert_raises(ArgumentError) { launch(template_key:"unavailable",request_key:"other-key-123") }
    assert_raises(ActiveRecord::RecordNotFound) { launch(user_id:@bob.id) }
  end
  def test_saved_show_is_site_scoped_and_episode_camera_references_are_independent
    camera=@scene.scene_objects.create!(name:"Master",object_type:"camera",definition:{location:[0,-5,1.2]})
    @scene.update!(settings:@scene.settings.merge("camera_cuts"=>[{"camera_id"=>camera.id,"frame"=>1}]))
    prop=@scene.scene_objects.create!(name:"Contact prop",object_type:"cube",definition:{location:[1,0,1]})
    actor=@scene.scene_objects.create!(name:"Contact actor",object_type:"cube",definition:{prop_contact:{target_object_id:prop.id}})
    template=action("template_save",project_id:@project.id,name:"My recurring show",request_key:SecureRandom.uuid)
    assert catalog[:saved_templates].any? { |row| row[:id]==template[:project_id] }
    result=launch(source:"saved",project_id:template[:project_id])
    copy=StudioScene.find(result["scenes"].first["id"])
    refute_equal camera.id,copy.settings["camera_cuts"].first["camera_id"]
    assert copy.scene_objects.where(object_type:"camera").exists?(id:copy.settings["camera_cuts"].first["camera_id"])
    copied_actor=copy.scene_objects.find_by!(name:"Contact actor")
    copied_prop=copy.scene_objects.find_by!(name:"Contact prop")
    assert_equal copied_prop.id,copied_actor.definition.dig("prop_contact","target_object_id")
    refute_equal prop.id,copied_prop.id
    foreign=StudioProject.create!(owner:@bob,site:@other_site,name:"Foreign template",is_template:true)
    assert_raises(ActiveRecord::RecordNotFound) { launch(source:"saved",project_id:foreign.id,request_key:"foreign-launch-123") }
    refute_includes catalog[:saved_templates].map { |row| row[:id] },foreign.id
  end
  def test_snapshot_preserves_set_definitions_cuts_and_copies_native_asset_sources
    model=StudioAsset.new(owner:@alice,site:@site,name:"Prop",kind:"blend",status:"ready",request_key:SecureRandom.uuid,metadata:{})
    model.native.attach(io:StringIO.new("original packed prop"),filename:"prop.blend",content_type:"application/x-blender",identify:false);model.file.attach(model.native.blob);model.save!
    prop=@scene.scene_objects.create!(name:"Frozen prop",object_type:"imported_asset",definition:{asset_id:model.id,location:[1,0,0]})
    camera=@scene.scene_objects.create!(name:"Master",object_type:"camera",definition:{location:[0,-5,1.2]})
    @scene.update!(settings:@scene.settings.merge("fps"=>24,"camera_cuts"=>[{"camera_id"=>camera.id,"frame"=>25}]))
    access=Studio::PwaAccess.new("user_id"=>@alice.id,"site_id"=>@site.id)
    snapshot=Studio::Performance::SceneTemplates.snapshot(access:access,source:@scene,key:"current")
    prop.update!(definition:prop.definition.merge("location"=>[9,9,9]))
    target=@project.studio_scenes.create!(name:"Prepared",settings:{"fps"=>12,"frame_end"=>36})
    Studio::Performance::SceneTemplates.apply!(target,snapshot,access:access)
    copied=target.scene_objects.find_by!(name:"Frozen prop")
    assert_equal [1,0,0],copied.definition["location"]
    refute_equal model.id,copied.definition["asset_id"]
    frozen=StudioAsset.find(copied.definition["asset_id"])
    assert_equal model.native.blob.id,frozen.native.blob.id
    assert_equal 13,target.reload.settings["camera_cuts"].first["frame"]
    assert target.scene_objects.exists?(id:target.settings["camera_cuts"].first["camera_id"],object_type:"camera")
    model.native.attach(io:StringIO.new("changed"),filename:"new.blend",content_type:"application/x-blender",identify:false)
    assert_equal "original packed prop",frozen.native.download
    assert_raises(ArgumentError) { Studio::Performance::SceneTemplates.apply!(@project.studio_scenes.create!(name:"Stale",settings:{}),snapshot,access:access) }
    assert_raises(ArgumentError) { prepare(scene_template:"arbitrary",request_key:"bad-scene-template") }
  end
  def test_current_scene_prefills_registered_cast_and_keeps_its_transform
    actor=ready_actor
    placement=action("cast_place",scene_id:@scene.id,asset_id:actor.id,lock_version:@scene.reload.lock_version,request_key:SecureRandom.uuid)
    object=SceneObject.find(placement["object_id"])
    object.update!(definition:object.definition.merge("location"=>[1,2,0.04]))
    defaults=catalog[:scene_templates].find { |row| row[:key]=="current" }[:defaults]
    assert_equal actor.id,defaults["cast_asset_id"]
    assert_equal actor.name,defaults["name"]
    parent=StudioOperation.find(prepare(scene_template:"current",cast_asset_id:actor.id)[:operation_id])
    assert_equal [1,2,0.04],parent.manifest.dig("staging","actor_transform","location")
    refute parent.manifest.dig("staging","objects").any? { |item| item.dig("definition","character_profile") }
    assert_equal actor.id,parent.manifest.dig("inputs","cast_asset_id")
  end
  def test_real_rooftop_template_reaches_the_performed_preview_with_template_cameras
    skip "Set LIGHTEK_TEST_CHARACTER_SCENE=1" unless ENV["LIGHTEK_TEST_CHARACTER_SCENE"]=="1"
    previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=Dir.mktmpdir("template-short-output-")
    Rails.stub(:root,Pathname(ROOT)) do
      parent=StudioOperation.find(prepare(scene_template:"library:tpl_night_exterior",camera_mode:"template",gesture:"nod")[:operation_id])
      assert parent.manifest.dig("staging","objects").any? { |object| object["name"]=="Rooftop deck" }
      StudioCharacterSceneJob.perform_now(parent.id)
      assert_equal "completed",parent.reload.status,parent.error_message
      scene=StudioScene.find(parent.metadata.fetch("scene_id"))
      assert scene.scene_objects.exists?(name:"Rooftop deck")
      assert_equal 3,scene.scene_objects.where(object_type:"camera").count
      assert_equal 2,scene.settings["camera_cuts"].length
      assert_equal "library:tpl_night_exterior",scene.settings.dig("template_source","key")
      actor=scene.scene_objects.find { |object| object.definition["character_profile"] }
      assert_equal "nod",actor.definition.dig("performance","gestures",0,"kind")
      child=StudioOperation.find(parent.metadata.fetch("preview_id"))
      video=child.artifacts.find_by!(kind:"video")
      video.file.blob.open do |file|
        metadata=JSON.parse(IO.popen(["ffprobe","-v","error","-show_streams","-show_format","-of","json",file.path],&:read))
        assert_in_delta 3,metadata.dig("format","duration").to_f,0.1
        assert metadata["streams"].any? { |stream| stream["codec_type"]=="audio" }
        FileUtils.cp(file.path,ENV["STUDIO_TEMPLATE_PROOF_VIDEO"]) if ENV["STUDIO_TEMPLATE_PROOF_VIDEO"]
      end
    end
  ensure
    ENV["BLENDER_OUTPUT_ROOT"]=previous if defined?(previous)
  end
end
