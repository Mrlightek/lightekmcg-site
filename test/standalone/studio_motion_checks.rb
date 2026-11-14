require_relative "studio_performance_checks"
require File.join(ROOT,"app/services/studio/performance/motion_plan")
class StudioMotionTest < StudioPerformanceTest
  StudioPerformanceTest.instance_methods(false).grep(/^test_/).each{|method|undef_method(method)}
  def performer
    return @motion_object if @motion_object
    @motion_object=placed_actor
    profile=@motion_object.definition.fetch("character_profile").merge("motions"=>[{"id"=>"head_action", "name"=>"Head nod","source"=>"Head nod","slot"=>"","rig"=>"Rig","fps"=>24.0,"frame_start"=>1.0,"frame_end"=>25.0}])
    @motion_object.update!(definition:@motion_object.definition.merge("character_profile"=>profile))
    @motion_object
  end
  def clip(**values)
    {"id"=>"clip-instance-123","action_id"=>"head_action","source_in"=>1,"source_out"=>25,"start"=>0,"speed"=>1,"repeat"=>1,"strength"=>1,"layer"=>0,"blend_in"=>0,"blend_out"=>0,"mode"=>"REPLACE"}.merge(values.transform_keys(&:to_s))
  end
  def save_motion(clips=[clip],**values)
    object=performer
    action("motion_save",scene_id:@scene.id,object_id:object.id,lock_version:@scene.reload.lock_version,motion_revision:object.reload.definition.fetch("motion_revision",0),clips:clips,request_key:SecureRandom.uuid,**values)
  end
  def test_motion_saves_retimes_and_snapshots_without_requiring_audio
    result=save_motion([clip(start:3,speed:0.5,repeat:2,strength:0.6,blend_in:0.5,blend_out:0.5)])
    object=performer.reload
    assert_equal 4,object.definition.dig("motion_clips",0,"duration")
    assert_equal 1,result["motion_revision"]
    assert_operator @scene.reload.settings["frame_end"],:>=,168
    preview=action("performance_preview",scene_id:@scene.id)
    operation=StudioOperation.find(preview[:operation_id]);assert_equal 1,operation.performance_sources.count
    assert_equal 73,operation.manifest.dig("scene","settings","frame_start")
    assert_equal object.definition["motion_clips"],operation.manifest.dig("scene","objects").find{|o|o["id"]==object.id}.dig("definition","motion_clips")
    save_motion([])
    assert_empty performer.reload.definition["motion_clips"]
    assert action("performance_preview",scene_id:@scene.id,operation_id:operation.id)[:stale]
  end
  def test_motion_requests_are_idempotent_and_stale_updates_never_overwrite
    object=performer;payload={scene_id:@scene.id,object_id:object.id,lock_version:@scene.reload.lock_version,motion_revision:0,clips:[clip],request_key:SecureRandom.uuid}
    first=action("motion_save",**payload)
    assert_equal first,action("motion_save",**payload)
    assert_raises(ArgumentError){action("motion_save",**payload.merge(clips:[clip(start:2)]))}
    assert_raises(ArgumentError){action("motion_save",**payload.merge(request_key:SecureRandom.uuid))}
    assert_raises(ArgumentError){save_motion([clip],motion_revision:0)}
    assert_equal 1,object.reload.definition["motion_revision"]
  end
  def test_motion_clips_validate_action_range_finite_values_bounds_and_layers
    profile=performer.definition["character_profile"]
    [clip(action_id:"not-this-rig"),clip(source_in:0),clip(source_out:30),clip(source_out:1),clip(speed:Float::NAN),clip(repeat:21),clip(repeat:1.5),clip(layer:0.5),clip(layer:4),clip(start:600),clip(blend_in:2),clip(strength:-1),clip(mode:"SCRIPT")].each do |raw|
      assert_raises(ArgumentError){Studio::Performance::MotionPlan.normalize([raw],profile)}
    end
    assert_raises(ArgumentError){Studio::Performance::MotionPlan.normalize([clip,clip],profile)}
    assert_raises(ArgumentError){Studio::Performance::MotionPlan.normalize([clip]*33,profile)}
    assert_raises(ArgumentError){save_motion([clip,clip(id:"second-clip",start:0.8)])}
    save_motion([clip(blend_out:0.25),clip(id:"second-clip",start:0.8,blend_in:0.25)])
    save_motion([clip,clip(id:"second-clip",start:0.1,layer:1,mode:"ADD")])
  end
  def test_motion_direction_is_independent_of_dialogue_and_copied_episodes
    object=performer;save_take(object);saved_take=object.reload.definition["performance"].deep_dup
    save_motion;assert_equal saved_take,object.reload.definition["performance"]
    template=action("template_save",project_id:@project.id,name:"Movement show",request_key:SecureRandom.uuid)
    episode=action("template_use",project_id:template[:project_id],name:"New episode",request_key:SecureRandom.uuid)
    copy=StudioScene.find(episode[:scene_id]);actor=copy.scene_objects.find_by!(object_type:"imported_asset")
    assert_nil copy.settings["motion_receipts"]
    action("motion_save",scene_id:copy.id,object_id:actor.id,lock_version:copy.lock_version,motion_revision:1,clips:[],request_key:SecureRandom.uuid)
    assert performer.reload.definition["motion_clips"].any?
    assert_empty actor.reload.definition["motion_clips"]
    save_take(object)
    assert object.reload.definition["motion_clips"].any?
  end
  def test_motion_native_import_exposes_only_source_assigned_actions
    skip "Set LIGHTEK_TEST_BLENDER=1" unless ENV["LIGHTEK_TEST_BLENDER"]=="1"
    result=action("cast_create",request_key:SecureRandom.uuid)
    Rails.stub(:root,Pathname(ROOT)){StudioCharacterCreateJob.perform_now(result[:asset_id])}
    actor=StudioAsset.find(result[:asset_id]);motions=actor.metadata.dig("character_profile","motions")
    assert_equal 3,motions.length
    assert_equal ["Head nod","Look left and right","Wave right"],motions.map{|item|item["name"]}.sort
    assert motions.all?{|item|item["rig"]=="PerformerRig" && item["fps"]>0 && item["frame_start"]==1 && item["frame_end"]==25}
    placed=action("cast_place",scene_id:@scene.id,asset_id:actor.id,lock_version:@scene.reload.lock_version,request_key:SecureRandom.uuid)
    object=SceneObject.find(placed["object_id"])
    saved=action("motion_save",scene_id:@scene.id,object_id:object.id,lock_version:@scene.reload.lock_version,motion_revision:0,clips:[clip(action_id:motions.first["id"])],request_key:SecureRandom.uuid)
    assert_equal 1,saved["motion_revision"]
  end
  def test_motion_foreign_scenes_and_objects_cannot_be_modified
    object=performer
    other=StudioProject.create!(owner:@bob,site:@other_site,name:"Other").studio_scenes.first
    assert_raises(ActiveRecord::RecordNotFound){save_motion([clip],scene_id:other.id)}
    assert_raises(ActiveRecord::RecordNotFound){save_motion([clip],site_id:@other_site.id)}
    assert_raises(ActiveRecord::RecordNotFound){save_motion([clip],object_id:other.scene_objects.create!(name:"Other object",object_type:"cube",definition:{"location"=>[0,0,0]}).id)}
    assert_nil object.reload.definition["motion_clips"]
  end
end
