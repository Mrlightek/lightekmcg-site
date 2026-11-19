require_relative "studio_contact_checks"
class StudioMechanicsTest < StudioContactTest
  StudioContactTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def bench(**extra)
    prepare(scene_template:"bench",gesture:"still",dialogue:"We can build this world together.",emotion:"friendly",mechanics:{action:"bench",version:1,target_id:"seat"},**extra)
  end
  def test_versioned_mechanics_inputs_profiles_and_frozen_targets
    result=bench;assert_equal result,bench
    assert_equal 1,result.dig(:inputs,"mechanics","version")
    assert_raises(ArgumentError) { bench(mechanics:{action:"bench",version:2,target_id:"seat"}) }
    assert_raises(ArgumentError) { bench(mechanics:{action:"script",version:1,target_id:"seat"}) }
    assert_raises(ArgumentError) { bench(mechanics:{action:"bench",version:1,target_id:"foreign"}) }
    assert_raises(ArgumentError) { bench(entrance:"from_left") }
    assert_raises(ArgumentError) { bench(body_action:"point_right") }
    assert_raises(ArgumentError) { bench(gesture:"wave_right") }
    assert_raises(ArgumentError) { bench(cast_asset_id:ready_actor.id) }
    assert_raises(ArgumentError) { dialogue(mechanics:{action:"bench",version:1,target_id:"seat"}) }
    assert_raises(ArgumentError) { Studio::Performance::Mechanics.register([],Studio::Performance::Mechanics.bindings.merge("version"=>2)) }
    assert_empty @scene.scene_objects
    assert action("character_scene_catalog",scene_id:@scene.id)[:scene_templates].find { |row| row[:key]=="bench" }[:mechanics_targets].any? { |row| row[:id]=="seat" }
  end
  def test_real_obstacle_still_blocks_the_coordinated_performance
    skip "Set LIGHTEK_TEST_CHARACTER_SCENE=1" unless ENV["LIGHTEK_TEST_CHARACTER_SCENE"]=="1"
    previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=Dir.mktmpdir("mechanics-collision-")
    Rails.stub(:root,Pathname(ROOT)) do
      parent=StudioOperation.find(bench[:operation_id]);manifest=parent.manifest.deep_dup
      manifest.fetch("staging").fetch("objects") << {"id"=>"blocker","name"=>"Walkway obstacle","type"=>"cube","definition"=>{"location"=>[-0.5,-0.24,1.3],"scale"=>[0.12,0.2,0.2]}}
      parent.update!(manifest:manifest)
      error=assert_raises(Blender::Runner::ExecutionError) { StudioCharacterSceneJob.perform_now(parent.id) }
      assert_includes error.message,"Environment collision"
      assert_equal "failed",parent.reload.status
    end
  ensure
    ENV["BLENDER_OUTPUT_ROOT"]=previous if defined?(previous)
  end
  def test_real_walk_turn_sit_speech_stand_support_and_editable_versioned_plan
    skip "Set LIGHTEK_TEST_CHARACTER_SCENE=1" unless ENV["LIGHTEK_TEST_CHARACTER_SCENE"]=="1"
    previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=Dir.mktmpdir("mechanics-proof-")
    Rails.stub(:root,Pathname(ROOT)) do
      parent=StudioOperation.find(bench[:operation_id]);StudioCharacterSceneJob.perform_now(parent.id)
      assert_equal "completed",parent.reload.status,parent.error_message
      scene=StudioScene.find(parent.metadata["scene_id"]);actor=scene.scene_objects.find { |row| row.definition["mechanics_plan"] }
      assert_equal 1,actor.definition.dig("mechanics_plan","version")
      assert_equal Studio::Performance::Mechanics.driver_fingerprint,actor.definition.dig("mechanics_plan","driver_fingerprint")
      assert_equal 96,scene.settings["frame_end"]
      assert_in_delta 3.4,actor.definition.dig("performance","start"),0.001
      assert_equal 1,scene.settings["camera_cuts"].size
      preview=StudioOperation.find(parent.metadata["preview_id"])
      preview.artifacts.find_by!(kind:"video").file.blob.open { |file| FileUtils.cp(file.path,ENV["STUDIO_MECHANICS_PROOF_VIDEO"]) if ENV["STUDIO_MECHANICS_PROOF_VIDEO"] }
      preview.artifacts.find_by!(kind:"blend").file.blob.open do |file|
        FileUtils.cp(file.path,ENV["STUDIO_MECHANICS_PROOF_BLEND"]) if ENV["STUDIO_MECHANICS_PROOF_BLEND"]
        script=File.join(Dir.mktmpdir,"verify-mechanics.py")
        File.write(script,<<~PYTHON)
          import bpy,json
          from mathutils import Vector
          scene=bpy.context.scene;root=bpy.data.objects['Sentinel'];report=json.loads(root['lightek_mechanics_report'])
          assert report['version']==1 and report['frames']==96 and report['support_frames']>20, report
          assert max(report['max_limb_error'],report['max_seat_error'],report['max_ground_error'])<.002, report
          rig=next(obj for obj in root.children_recursive if obj.type=='ARMATURE')
          support=next(obj for obj in root.children_recursive if obj.get('lightek_source_object')=='Pelvis support')
          feet=[next(obj for obj in root.children_recursive if obj.get('lightek_source_object')=='Boot '+side) for side in ('L','R')]
          seat=bpy.data.objects['Bench seat'];positions=[];yaws=[];support_heights=[];anchors=[]
          for frame in range(1,97):
              scene.frame_set(frame);positions.append(root.location.x);yaws.append(root.rotation_quaternion.angle);support_heights.append(support.matrix_world.translation.z)
              if 41<=frame<=76:
                  point=support.matrix_world @ Vector((0,.004,-.0832))
                  assert abs(point.z-(seat.matrix_world @ Vector((0,0,1))).z)<.002
              if frame>=32:
                  points=[foot.matrix_world @ Vector((0,.004,-.104)) for foot in feet]
                  assert all(abs(point.z)<.002 for point in points)
                  anchors.append(points)
          assert positions[-1]-positions[0]>.79 and max(yaws)>.3 and yaws[-1]<.001
          assert max(support_heights)-min(support_heights)>.24
          assert max((points[i]-anchors[0][i]).length for points in anchors for i in range(2))<.002
          assert rig.animation_data and all(foot.animation_data for foot in feet)
          assert any(sound.packed_file for sound in bpy.data.sounds)
          print('MECHANICS_SUPPORT_VERIFIED',report)
        PYTHON
        output=Studio::MediaProcess.run!([ENV.fetch("BLENDER_BIN","blender"),"--background","--disable-autoexec",file.path,"--python-exit-code","1","--python",script],timeout:60)
        assert_includes output,"MECHANICS_SUPPORT_VERIFIED"
      end
      counts=[StudioAsset.count,SceneObject.count,StudioOperation.count];original=actor.definition["mechanics_plan"].deep_dup
      parent.update!(status:"failed");action("character_scene_retry",operation_id:parent.id);StudioCharacterSceneJob.perform_now(parent.id)
      assert_equal "completed",parent.reload.status
      assert_equal counts,[StudioAsset.count,SceneObject.count,StudioOperation.count]
      assert_equal original,actor.reload.definition["mechanics_plan"]
      invalid=preview.reload.manifest.deep_dup
      invalid.fetch("scene").fetch("objects").find { |row| row.dig("definition","mechanics_plan") }.fetch("definition").fetch("mechanics_plan")["driver_fingerprint"]="changed-code"
      preview.update!(manifest:invalid,status:"pending")
      error=assert_raises(Blender::Runner::ExecutionError) { StudioBlenderPreviewJob.perform_now(preview.id) }
      assert_includes error.message,"pinned mechanics implementation changed"
      assert_equal "failed",preview.reload.status
    end
  ensure
    ENV["BLENDER_OUTPUT_ROOT"]=previous if defined?(previous)
  end
end
