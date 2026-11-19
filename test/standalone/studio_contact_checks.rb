require_relative "studio_acting_checks"
class StudioContactTest < StudioActingTest
  StudioActingTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def touch(**extra)
    prepare(dialogue:"Panel activated.",scene_template:"control_panel",emotion:"friendly",entrance:"from_left",contact:{target_id:"button",face:"front",hand:"right",start:1.1,reach:0.5,hold:0.5,release:0.5},**extra)
  end
  def test_contact_inputs_are_scoped_bounded_frozen_and_source_bound
    result=touch;assert_equal result,touch
    assert_equal "button",result.dig(:inputs,"contact","target_id")
    assert_raises(ArgumentError) { touch(contact:{target_id:"unrelated"}) }
    assert_raises(ArgumentError) { touch(contact:{target_id:"button",hand:"execute"}) }
    assert_raises(ArgumentError) { touch(contact:{target_id:"button",face:"inside"}) }
    assert_raises(ArgumentError) { touch(contact:{target_id:"button",start:Float::NAN}) }
    assert_raises(ArgumentError) { touch(contact:{target_id:"button",start:5,reach:1.5,hold:2,release:1.5}) }
    assert_raises(ArgumentError) { touch(body_action:"point_right") }
    assert_raises(ArgumentError) { touch(gesture:"wave_right") }
    assert_raises(ArgumentError) { touch(contact:{target_id:"button",start:0.5}) }
    assert_raises(ArgumentError) { Studio::Performance::Contact.validate_profile!({"contact"=>{"hand"=>"right"}},ready_actor.metadata["character_profile"]) }
    assert action("character_scene_catalog",scene_id:@scene.id)[:scene_templates].find { |row| row[:key]=="control_panel" }[:contact_targets].any? { |row| row[:id]=="button" }
    assert_raises(ArgumentError) { touch(cast_asset_id:ready_actor.id) }
    assert_empty @scene.scene_objects
  end
  def test_shared_prop_overlap_and_frozen_target_identity
    cue={target_id:"button",start:1.1,reach:0.5,hold:0.5,release:0.5}
    assert_raises(ArgumentError) { dialogue(scene_template:"control_panel",characters:[{name:"A",contact:cue},{name:"B",contact:cue}]) }
    result=touch;op=StudioOperation.find(result[:operation_id])
    assert op.manifest.fetch("staging").fetch("objects").any? { |object| object["id"]=="button" }
    assert_raises(ActiveRecord::RecordNotFound) { action("character_scene_status",operation_id:op.id,user_id:@bob.id) }
  end
  def test_real_dialogue_combines_entrance_button_contact_speech_and_listener_reaction
    skip "Set LIGHTEK_TEST_CHARACTER_SCENE=1 with native tools" unless ENV["LIGHTEK_TEST_CHARACTER_SCENE"]=="1"
    previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=Dir.mktmpdir("contact-dialogue-")
    Rails.stub(:root,Pathname(ROOT)) do
      result=dialogue(scene_template:"control_panel",characters:[{name:"Sentinel",voice:"en-us",emotion:"friendly",entrance:"from_left",contact:{target_id:"button",start:1.1,reach:0.5,hold:0.5,release:0.5}},{name:"Beacon",voice:"en-gb",emotion:"curious",wardrobe:"#945228"}],turns:[{speaker:0,dialogue:"Panel activated."},{speaker:1,dialogue:"We are ready."}])
      parent=StudioOperation.find(result[:operation_id]);StudioCharacterSceneJob.perform_now(parent.id)
      assert_equal "completed",parent.reload.status,parent.error_message
      scene=StudioScene.find(parent.metadata["scene_id"])
      cast=scene.scene_objects.select { |object| object.definition["character_profile"] }
      assert_equal 2,cast.size
      assert cast.all? { |object| object.definition["listener_reactions"].any? }
      assert_equal 1,cast.count { |object| object.definition["prop_contact"] }
      assert_operator scene.settings["frame_end"],:<=,96
      preview=StudioOperation.find(parent.metadata["preview_id"])
      preview.artifacts.find_by!(kind:"video").file.blob.open { |file| FileUtils.cp(file.path,ENV["STUDIO_CONTACT_DIALOGUE_PROOF_VIDEO"]) if ENV["STUDIO_CONTACT_DIALOGUE_PROOF_VIDEO"] }
    end
  ensure
    ENV["BLENDER_OUTPUT_ROOT"]=previous if defined?(previous)
  end
  def test_real_environment_collision_still_rejects_contact_preview
    skip "Set LIGHTEK_TEST_CHARACTER_SCENE=1 with native tools" unless ENV["LIGHTEK_TEST_CHARACTER_SCENE"]=="1"
    previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=Dir.mktmpdir("contact-blocked-")
    Rails.stub(:root,Pathname(ROOT)) do
      parent=StudioOperation.find(touch[:operation_id]);manifest=parent.manifest.deep_dup
      manifest.fetch("staging").fetch("objects") << {"id"=>"obstacle","name"=>"Blocking obstacle","type"=>"cube","definition"=>{"location"=>[0,0,1.2],"scale"=>[0.3,0.3,0.3]}}
      parent.update!(manifest:manifest)
      error=assert_raises(Blender::Runner::ExecutionError) { StudioCharacterSceneJob.perform_now(parent.id) }
      assert_includes error.message,"Environment collision"
      assert_equal "failed",parent.reload.status
      refute_equal "completed",StudioOperation.find(parent.metadata["preview_id"]).status
    end
  ensure
    ENV["BLENDER_OUTPUT_ROOT"]=previous if defined?(previous)
  end
  def test_real_unreachable_target_is_rejected_without_successful_preview
    skip "Set LIGHTEK_TEST_CHARACTER_SCENE=1 with native tools" unless ENV["LIGHTEK_TEST_CHARACTER_SCENE"]=="1"
    previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=Dir.mktmpdir("contact-reject-")
    Rails.stub(:root,Pathname(ROOT)) do
      parent=StudioOperation.find(touch[:operation_id]);manifest=parent.manifest.deep_dup
      manifest.fetch("staging").fetch("objects").find { |object| object["id"]=="button" }.fetch("definition")["location"]=[5,-0.095,1.2]
      parent.update!(manifest:manifest)
      error=assert_raises(Blender::Runner::ExecutionError) { StudioCharacterSceneJob.perform_now(parent.id) }
      assert_includes error.message,"outside the natural arm reach"
      assert_equal "failed",parent.reload.status
      refute_equal "completed",StudioOperation.find(parent.metadata["preview_id"]).status
    end
  ensure
    ENV["BLENDER_OUTPUT_ROOT"]=previous if defined?(previous)
  end
  def test_real_palm_contact_wrist_continuity_button_response_and_editable_bake
    skip "Set LIGHTEK_TEST_CHARACTER_SCENE=1 with native tools" unless ENV["LIGHTEK_TEST_CHARACTER_SCENE"]=="1"
    previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=Dir.mktmpdir("contact-output-")
    Rails.stub(:root,Pathname(ROOT)) do
      parent=StudioOperation.find(touch[:operation_id]);StudioCharacterSceneJob.perform_now(parent.id)
      assert_equal "completed",parent.reload.status,parent.error_message
      scene=StudioScene.find(parent.metadata["scene_id"])
      actor=scene.scene_objects.find { |object| object.definition["prop_contact"] }
      cue=actor.definition["prop_contact"];target=scene.scene_objects.find(cue["target_object_id"])
      assert_equal "Activation button",target.name
      assert_equal "right",cue["hand"]
      assert actor.definition["character_profile"].dig("reach_bindings","right")
      preview=StudioOperation.find(parent.metadata["preview_id"])
      preview.artifacts.find_by!(kind:"video").file.blob.open { |file| FileUtils.cp(file.path,ENV["STUDIO_CONTACT_PROOF_VIDEO"]) if ENV["STUDIO_CONTACT_PROOF_VIDEO"] }
      preview.artifacts.find_by!(kind:"blend").file.blob.open do |file|
        script=File.join(Dir.mktmpdir,"verify-contact.py")
        File.write(script,<<~PYTHON)
          import bpy,json
          from mathutils import Vector
          scene=bpy.context.scene
          report=json.loads(scene['lightek_contact_report'])
          assert len(report)==1 and report[0]['measured_frames']>=3, report
          assert report[0]['max_contact_error']<.002 and report[0]['max_wrist_error']<.002, report
          root=bpy.data.objects['Sentinel'];rig=next(obj for obj in root.children_recursive if obj.type=='ARMATURE')
          hand=next(obj for obj in root.children_recursive if obj.get('lightek_source_object')=='Hand R')
          prop=bpy.data.objects['Activation button'];marker=next(obj for obj in scene.objects if obj.get('lightek_contact_actor') is not None)
          assert marker.parent==prop
          distances=[];depths=[]
          for frame in range(1,scene.frame_end+1):
              scene.frame_set(frame)
              depths.append(prop.location.y)
              if #{cue['start']+cue['reach']}-1e-6<=(frame-1)/12<=#{cue['start']+cue['reach']+cue['hold']}+1e-6:
                  distances.append(((hand.matrix_world @ Vector((0,.004,0)))-(prop.matrix_world @ Vector((0,-1,0)))).length)
                  assert ((hand.matrix_world @ Vector((0,0,.12)))-(rig.matrix_world @ rig.pose.bones['Forearm.R'].tail)).length<.002
          assert distances and max(distances)<.002, distances
          assert max(depths)-min(depths)>.008, depths
          assert hand.animation_data and rig.animation_data
          assert any(sound.packed_file for sound in bpy.data.sounds)
          print('PROP_CONTACT_VERIFIED')
        PYTHON
        output=Studio::MediaProcess.run!([ENV.fetch("BLENDER_BIN","blender"),"--background","--disable-autoexec",file.path,"--python-exit-code","1","--python",script],timeout:60)
        assert_includes output,"PROP_CONTACT_VERIFIED"
      end
      counts=[StudioAsset.count,SceneObject.count,StudioOperation.count]
      parent.update!(status:"failed");action("character_scene_retry",operation_id:parent.id);StudioCharacterSceneJob.perform_now(parent.id)
      assert_equal "completed",parent.reload.status
      assert_equal counts,[StudioAsset.count,SceneObject.count,StudioOperation.count]
    end
  ensure
    ENV["BLENDER_OUTPUT_ROOT"]=previous if defined?(previous)
  end
end
