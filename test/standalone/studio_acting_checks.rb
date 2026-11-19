require_relative "studio_dialogue_scene_checks"
class StudioActingTest < StudioDialogueSceneTest
  StudioDialogueSceneTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def test_guided_direction_is_bounded_source_bound_and_part_of_request_identity
    result=prepare(emotion:"friendly",body_action:"point_right",entrance:"from_left")
    assert_equal "friendly",result.dig(:inputs,"emotion")
    assert_equal result,prepare(emotion:"friendly",body_action:"point_right",entrance:"from_left")
    assert_raises(ArgumentError) { prepare(emotion:"curious",body_action:"point_right",entrance:"from_left") }
    assert_raises(ArgumentError) { prepare(body_action:"point_right",gesture:"wave_right") }
    assert_raises(ArgumentError) { prepare(emotion:"script") }
    assert_raises(ArgumentError) { prepare(body_action:"/tmp/source.py") }
    assert_raises(ArgumentError) { prepare(entrance:Float::NAN) }
    assert_raises(ArgumentError) { dialogue(characters:[{name:"A",emotion:"unbound"},{name:"B"}]) }
    profile=ready_actor.metadata.fetch("character_profile")
    assert_raises(ArgumentError) { Studio::Performance::Acting.validate!({"body_action"=>"point_right"},profile) }
    assert_raises(ArgumentError) { Studio::Performance::Acting.validate!({"entrance"=>"from_left"},profile) }
    assert_raises(ArgumentError) { Studio::Performance::Acting.validate!({"emotion"=>"curious"},profile) }
    assert_empty Studio::Performance::Acting.expressions({"emotion"=>"neutral"},profile,1)
  end
  def test_interrupted_acting_save_rolls_back_motion_receipt_and_retries_as_one_arrangement
    object=placed_actor;profile=object.definition["character_profile"].deep_dup
    profile["motions"]=[{"id"=>"point-local-action","name"=>"Point right","rig"=>"Rig","frame_start"=>1,"frame_end"=>25,"fps"=>24}]
    object.update!(definition:object.definition.merge("character_profile"=>profile))
    access=Studio::PwaAccess.new("user_id"=>@alice.id,"site_id"=>@site.id)
    arguments={access:access,scene:@scene,object:object,character:{"emotion"=>"neutral","body_action"=>"point_right","entrance"=>"none"},turns:[{"start"=>0.1,"duration"=>1}],key:"acting-atomic-request-123"}
    object.stub(:update!,->(**_) { raise "Interrupted after motion save" }) do
      assert_raises(RuntimeError) { Studio::Performance::Acting.apply!(**arguments) }
    end
    refute object.reload.definition.key?("motion_clips")
    refute @scene.reload.settings.fetch("motion_receipts",{}).key?("acting-atomic-request-123-motion")
    Studio::Performance::Acting.apply!(**arguments)
    assert_equal 1,object.reload.definition["motion_clips"].size
    original=object.definition.deep_dup
    Studio::Performance::Acting.apply!(**arguments)
    assert_equal original,object.reload.definition
  end
  def test_real_dialogue_keeps_entrances_body_actions_and_reactions_in_the_eight_second_budget
    skip "Set LIGHTEK_TEST_CHARACTER_SCENE=1 with native tools" unless ENV["LIGHTEK_TEST_CHARACTER_SCENE"]=="1"
    previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=Dir.mktmpdir("acting-dialogue-")
    Rails.stub(:root,Pathname(ROOT)) do
      parent=StudioOperation.find(dialogue(characters:[{name:"Sentinel",voice:"en-us",emotion:"friendly",body_action:"point_right",entrance:"from_left"},{name:"Beacon",voice:"en-gb",emotion:"curious",body_action:"point_left",entrance:"from_right",wardrobe:"#945228"}])[:operation_id])
      StudioCharacterSceneJob.perform_now(parent.id)
      assert_equal "completed",parent.reload.status,parent.error_message
      scene=StudioScene.find(parent.metadata["scene_id"])
      assert_operator scene.settings["frame_end"],:<=,96
      assert_in_delta 1.1,scene.settings.dig("dialogue_timing",0,"start"),0.001
      objects=scene.scene_objects.select { |object| object.definition["character_profile"] }
      assert_equal 2,objects.size
      objects.each do |object|
        assert_equal 2,object.definition["motion_clips"].size
        assert_equal 12,object.definition.dig("animation","fps")
        assert object.definition["listener_reactions"].any?
      end
      assert_equal ["friendly","curious"],objects.map { |object| object.definition.dig("acting_direction","emotion") }
      preview=StudioOperation.find(parent.metadata["preview_id"])
      preview.artifacts.find_by!(kind:"video").file.blob.open do |file|
        info=JSON.parse(IO.popen(["ffprobe","-v","error","-show_streams","-show_format","-of","json",file.path],&:read))
        assert_equal "12/1",info["streams"].find { |stream| stream["codec_type"]=="video" }["r_frame_rate"]
        assert_in_delta parent.metadata["duration_seconds"],info["format"]["duration"].to_f,0.1
        FileUtils.cp(file.path,ENV["STUDIO_ACTING_DIALOGUE_PROOF_VIDEO"]) if ENV["STUDIO_ACTING_DIALOGUE_PROOF_VIDEO"]
      end
    end
  ensure
    ENV["BLENDER_OUTPUT_ROOT"]=previous if defined?(previous)
  end
  def test_real_illustrated_step_point_and_facial_cue_remain_editable_and_do_not_replay_on_retry
    skip "Set LIGHTEK_TEST_CHARACTER_SCENE=1 with native tools" unless ENV["LIGHTEK_TEST_CHARACTER_SCENE"]=="1"
    previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=Dir.mktmpdir("acting-output-")
    Rails.stub(:root,Pathname(ROOT)) do
      parent=StudioOperation.find(prepare(dialogue:"We will protect this city together.",emotion:"friendly",body_action:"point_right",entrance:"from_left",gesture:"still")[:operation_id])
      StudioCharacterSceneJob.perform_now(parent.id)
      assert_equal "completed",parent.reload.status,parent.error_message
      scene=StudioScene.find(parent.metadata["scene_id"])
      object=scene.scene_objects.find { |item| item.definition["character_profile"] }
      assert_equal 48,scene.settings["frame_end"]
      assert_equal 2,object.definition.fetch("motion_clips").size
      assert_equal "from_left",object.definition.dig("acting_direction","entrance")
      assert_equal 12,object.definition.dig("animation","fps")
      assert_in_delta 1.0,object.definition.dig("performance","start"),0.001
      source=StudioAsset.find(parent.metadata["cast_asset_id"])
      names=source.metadata.dig("character_profile","motions").map { |row| row["name"] }
      assert_includes names,"Step in place";assert_includes names,"Point right"
      preview=StudioOperation.find(parent.metadata["preview_id"])
      preview.artifacts.find_by!(kind:"video").file.blob.open do |file|
        info=JSON.parse(IO.popen(["ffprobe","-v","error","-show_streams","-show_format","-of","json",file.path],&:read))
        assert_equal "12/1",info["streams"].find { |stream| stream["codec_type"]=="video" }["r_frame_rate"]
        assert_in_delta scene.settings["frame_end"]/12.0,info["format"]["duration"].to_f,0.1
        FileUtils.cp(file.path,ENV["STUDIO_ACTING_PROOF_VIDEO"]) if ENV["STUDIO_ACTING_PROOF_VIDEO"]
      end
      preview.artifacts.find_by!(kind:"blend").file.blob.open do |file|
        root=Dir.mktmpdir;script=File.join(root,"verify-acting.py")
        File.write(script,<<~PYTHON)
          import bpy
          scene=bpy.context.scene
          root=bpy.data.objects.get('Sentinel')
          assert root is not None
          rig=next(obj for obj in scene.objects if obj.type=='ARMATURE')
          assert all(name in rig.pose.bones for name in ('Leg.L','Leg.R'))
          positions=[];legs=[];arms=[];smiles=[]
          face=next(obj for obj in scene.objects if obj.type=='MESH' and obj.get('lightek_source_object')=='FaceMouth')
          for frame in range(1,scene.frame_end+1):
              scene.frame_set(frame)
              positions.append(round(root.location.x,4))
              legs.append(tuple(round(v,4) for v in rig.pose.bones['Leg.L'].rotation_euler))
              arms.append(tuple(round(v,4) for v in rig.pose.bones['Arm.R'].rotation_euler))
              smiles.append(face.data.shape_keys.key_blocks['smile'].value)
          assert len(set(positions[:12]))>5 and abs(positions[0]-positions[11])>.7, positions
          assert len(set(legs[:12]))>3, legs
          assert len(set(arms[12:]))>2, arms
          assert max(smiles)>.4, smiles
          assert any(sound.packed_file for sound in bpy.data.sounds)
          print('GUIDED_ACTING_VERIFIED')
        PYTHON
        output=Studio::MediaProcess.run!([ENV.fetch("BLENDER_BIN","blender"),"--background","--disable-autoexec",file.path,"--python-exit-code","1","--python",script],timeout:60)
        assert_includes output,"GUIDED_ACTING_VERIFIED"
      end
      original=object.reload.definition.deep_dup;counts=[StudioAsset.count,SceneObject.count,StudioOperation.count]
      parent.update!(status:"failed");action("character_scene_retry",operation_id:parent.id);StudioCharacterSceneJob.perform_now(parent.id)
      assert_equal "completed",parent.reload.status
      assert_equal original,object.reload.definition
      assert_equal counts,[StudioAsset.count,SceneObject.count,StudioOperation.count]
    end
  ensure
    ENV["BLENDER_OUTPUT_ROOT"]=previous if defined?(previous)
  end
end
