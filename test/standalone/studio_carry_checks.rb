require_relative "studio_directional_checks"
class StudioCarryTest < StudioMechanicsTest
  StudioMechanicsTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def carry(**extra)
    prepare(scene_template:"carry",gesture:"still",dialogue:"I have got it. Let us move.",mechanics:{action:"carry",version:1,target_id:"parcel"},**extra)
  end
  def test_scoped_calibrated_carry_and_profile_inputs
    result=carry;assert_equal result,carry
    assert_raises(ArgumentError) { carry(mechanics:{action:"carry",version:1,target_id:"unrelated"}) }
    assert_raises(ArgumentError) { carry(mechanics:{action:"carry",version:2,target_id:"parcel"}) }
    assert_raises(ArgumentError) { carry(cast_asset_id:ready_actor.id) }
    assert_raises(ArgumentError) { carry(entrance:"from_left") }
    assert_empty @scene.scene_objects
  end
  def test_real_carried_parcel_collides_with_environment
    skip "Set LIGHTEK_TEST_CHARACTER_SCENE=1" unless ENV["LIGHTEK_TEST_CHARACTER_SCENE"]=="1"
    previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=Dir.mktmpdir("carry-obstacle-")
    Rails.stub(:root,Pathname(ROOT)) do
      parent=StudioOperation.find(carry[:operation_id]);manifest=parent.manifest.deep_dup
      manifest.fetch("staging").fetch("objects") << {"id"=>"parcel_blocker","name"=>"Parcel obstacle","type"=>"cube","definition"=>{"location"=>[0.3,-1.03,1.15],"scale"=>[0.06,0.06,0.06]}}
      parent.update!(manifest:manifest)
      error=assert_raises(Blender::Runner::ExecutionError) { StudioCharacterSceneJob.perform_now(parent.id) }
      assert_includes error.message,"Carried prop collision"
      assert_equal "failed",parent.reload.status
    end
  ensure
    ENV["BLENDER_OUTPUT_ROOT"]=previous if defined?(previous)
  end
  def test_real_pickup_attachment_sideways_carry_and_supported_release
    skip "Set LIGHTEK_TEST_CHARACTER_SCENE=1" unless ENV["LIGHTEK_TEST_CHARACTER_SCENE"]=="1"
    previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=Dir.mktmpdir("carry-proof-")
    Rails.stub(:root,Pathname(ROOT)) do
      parent=StudioOperation.find(carry[:operation_id]);StudioCharacterSceneJob.perform_now(parent.id)
      assert_equal "completed",parent.reload.status,parent.error_message
      scene=StudioScene.find(parent.metadata["scene_id"]);actor=scene.scene_objects.find { |row| row.definition["mechanics_plan"] }
      assert_equal "carry",actor.definition.dig("mechanics_plan","driver")
      assert_in_delta 2.3,actor.definition.dig("performance","start"),0.001
      assert_equal %w[pickup putdown],actor.definition.dig("mechanics_plan","support_object_ids").keys.sort
      preview=StudioOperation.find(parent.metadata["preview_id"])
      preview.artifacts.find_by!(kind:"video").file.blob.open { |file| FileUtils.cp(file.path,ENV["STUDIO_CARRY_PROOF_VIDEO"]) if ENV["STUDIO_CARRY_PROOF_VIDEO"] }
      preview.artifacts.find_by!(kind:"blend").file.blob.open do |file|
        FileUtils.cp(file.path,ENV["STUDIO_CARRY_PROOF_BLEND"]) if ENV["STUDIO_CARRY_PROOF_BLEND"]
        script=File.join(Dir.mktmpdir,"verify-carry.py")
        File.write(script,<<~PYTHON)
          import bpy,json
          from mathutils import Vector
          scene=bpy.context.scene;root=bpy.data.objects['Sentinel'];prop=bpy.data.objects['Carry parcel'];grip=prop.constraints['Lightek rigid palm grip'];hand=grip.target
          report=json.loads(root['lightek_mechanics_report'])
          assert max(report['max_grip_error'],report['max_support_error'],report['release_drift'],report['max_limb_error'],report['max_ground_error'])<.002, report
          released=[];travel=[]
          for frame in range(1,97):
              scene.frame_set(frame);travel.append(prop.matrix_world.translation.copy())
              assert grip.influence==(1 if 10<=frame<67 else 0)
              if 10<=frame<67:assert ((hand.matrix_world @ Vector((0,.004,0)))-(prop.matrix_world @ Vector((0,-1,1)))).length<.002
              if 30<=frame<=50:assert (root.rotation_quaternion @ Vector((0,-1,0))).dot(Vector((1,0,0)))>.999
              if frame>=67:released.append(prop.matrix_world.translation.copy())
          assert max(p.z for p in travel)-travel[0].z>.05
          assert abs(released[0].x+.03)<.002 and abs(released[0].y+.1)<.002 and abs(released[0].z-1.08)<.002
          assert max((p-released[0]).length for p in released)<.002
          assert any(sound.packed_file for sound in bpy.data.sounds)
          print('RIGID_GRIP_RELEASE_VERIFIED')
        PYTHON
        output=Studio::MediaProcess.run!([ENV.fetch("BLENDER_BIN","blender"),"--background","--disable-autoexec",file.path,"--python-exit-code","1","--python",script],timeout:60)
        assert_includes output,"RIGID_GRIP_RELEASE_VERIFIED"
      end
      counts=[StudioAsset.count,SceneObject.count,StudioOperation.count];parent.update!(status:"failed");action("character_scene_retry",operation_id:parent.id);StudioCharacterSceneJob.perform_now(parent.id)
      assert_equal "completed",parent.reload.status
      assert_equal counts,[StudioAsset.count,SceneObject.count,StudioOperation.count]
    end
  ensure
    ENV["BLENDER_OUTPUT_ROOT"]=previous if defined?(previous)
  end
end
