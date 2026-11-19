require_relative "studio_mechanics_checks"
class StudioGraspTest < StudioMechanicsTest
  StudioMechanicsTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def grasp_version = 1
  def grasp(**extra)
    prepare(scene_template:"grasp",camera_mode:"template",gesture:"still",dialogue:"A real grip.",mechanics:{action:"grasp",version:grasp_version,target_id:"ball"},**extra)
  end
  def test_scoped_physics_template_inputs_and_profile
    first=grasp;assert_equal first,grasp
    assert_raises(ArgumentError) { grasp(mechanics:{action:"grasp",version:1,target_id:"foreign"}) }
    assert_raises(ArgumentError) { grasp(mechanics:{action:"grasp",version:99,target_id:"ball"}) }
    assert_raises(ArgumentError) { grasp(gesture:"wave_right") }
    profile=Studio::Performance::Grasp.physical_profile
    assert_equal "kg",profile.dig("units","mass")
    row=action("character_scene_catalog",scene_id:@scene.id)[:scene_templates].find { |item| item[:key]=="grasp" }
    assert_equal "grasp",row[:mechanics_targets].first[:action]
    assert_equal "template",row[:defaults]["camera_mode"]
    staging=StudioOperation.find(first[:operation_id]).manifest["staging"].deep_dup
    staging["objects"].find { |item| item["id"]=="ball" }["definition"]["scale"]=[0.1,0.1,0.1]
    assert_raises(ArgumentError) { Studio::Performance::Grasp.validate!({"target_id"=>"ball"},staging) }
  end
  def test_physical_load_still_rejects_an_environment_obstacle
    skip "Set LIGHTEK_TEST_CHARACTER_SCENE=1" unless ENV["LIGHTEK_TEST_CHARACTER_SCENE"]=="1"
    previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=Dir.mktmpdir("grasp-obstacle-")
    Rails.stub(:root,Pathname(ROOT)) do
      parent=StudioOperation.find(grasp[:operation_id]);manifest=parent.manifest.deep_dup
      manifest.fetch("staging").fetch("objects") << {"id"=>"load_blocker","name"=>"Grip obstacle","type"=>"cube","definition"=>{"location"=>[-0.83,-0.24,1.16],"scale"=>[0.025,0.025,0.025]}}
      parent.update!(manifest:manifest)
      error=assert_raises(Blender::Runner::ExecutionError) { StudioCharacterSceneJob.perform_now(parent.id) }
      assert_includes error.message,"Physical load collision"
      assert_equal "failed",parent.reload.status
    end
  ensure
    ENV["BLENDER_OUTPUT_ROOT"]=previous if defined?(previous)
  end
  def test_real_contact_grip_lift_release_and_editable_finger_keys
    skip "Set LIGHTEK_TEST_CHARACTER_SCENE=1" unless ENV["LIGHTEK_TEST_CHARACTER_SCENE"]=="1"
    previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=Dir.mktmpdir("grasp-proof-")
    Rails.stub(:root,Pathname(ROOT)) do
      parent=StudioOperation.find(grasp[:operation_id]);StudioCharacterSceneJob.perform_now(parent.id)
      assert_equal "completed",parent.reload.status,parent.error_message
      scene=StudioScene.find(parent.metadata["scene_id"]);actor=scene.scene_objects.find { |row| row.definition["mechanics_plan"] }
      assert_equal Studio::Performance::Grasp.physical_profile,actor.definition.dig("mechanics_plan","physical_profile")
      assert_equal(grasp_version==3 ? 5 : 3,scene.settings["camera_cuts"].size)
      preview=StudioOperation.find(parent.metadata["preview_id"])
      preview.artifacts.find_by!(kind:"video").file.blob.open { |file| FileUtils.cp(file.path,ENV["STUDIO_GRASP_PROOF_VIDEO"]) if ENV["STUDIO_GRASP_PROOF_VIDEO"] }
      preview.artifacts.find_by!(kind:"blend").file.blob.open do |file|
        FileUtils.cp(file.path,ENV["STUDIO_GRASP_PROOF_BLEND"]) if ENV["STUDIO_GRASP_PROOF_BLEND"]
        script=File.join(Dir.mktmpdir,"verify-grasp.py")
        File.write(script,<<~PYTHON)
          import bpy,json
          from mathutils import Vector
          scene=bpy.context.scene;root=bpy.data.objects['Sentinel'];prop=bpy.data.objects['Contact sphere']
          report=json.loads(root['lightek_mechanics_report'])
          assert report['solver']=='mujoco' and report['solver_version']=='3.3.7',report
          assert not prop.constraints and not prop.parent and not report['whole_body_dynamics']
          assert report['max_penetration_m']<.002 and report['max_wrist_error_m']<.002 and report['max_ground_error_m']<.002,report
          assert report['max_finger_torque_nm']<=.350001 and report['lift_m']>.13,report
          assert 5<=report['min_elbow_flexion_deg']<=report['max_elbow_flexion_deg']<=145,report
          pads=[obj for obj in root.children_recursive if obj.get('lightek_capsule_radius_m')]
          assert len(pads)==15 and all(obj.animation_data for obj in pads)
          positions=[]
          for frame in range(1,97):
              scene.frame_set(frame);positions.append(prop.matrix_world.translation.copy())
          assert max(p.z for p in positions)-positions[0].z>.13
          assert abs(positions[-1].z-1)<.002 and abs(positions[-1].x+.83)<.01
          assert abs(positions[-1].z-positions[-12].z)<.002
          assert all(abs(p.x+.83)<.135 and abs(p.y+.24)<.155 for p in positions[-12:])
          if #{grasp_version}>=2:
              rig=next(obj for obj in root.children_recursive if obj.type=='ARMATURE')
              for frame in range(1,97):
                  scene.frame_set(frame);bpy.context.view_layer.update()
                  front=root.matrix_world.to_quaternion() @ Vector((0,-1,0))
                  target=prop.matrix_world.translation-root.matrix_world.translation;target.z=0
                  assert front.dot(target.normalized())>.99, (frame,front,target)
                  for side in ('L','R'):
                      upper=rig.pose.bones['Arm.'+side];lower=rig.pose.bones['Forearm.'+side]
                      shoulder=rig.matrix_world @ upper.head
                      assert ((rig.matrix_world @ lower.head)-shoulder).dot(front)>=-.002
                      assert ((rig.matrix_world @ lower.tail)-shoulder).dot(front)>=-.002
              assert report['object_attention']['head_nod_deg'][0]>=(10 if #{grasp_version}==3 else 20)
              assert report['object_attention']['pupil_down_m']>.02
              assert all(obj.data.shape_keys.key_blocks.get('grasp_look_down_v#{grasp_version}') for obj in root.children_recursive if obj.get('lightek_source_object') in ('FaceEyes','Side pupil','Side pupil reverse'))
          if #{grasp_version}==3:
              assert report['body_clearance_checked_frames']==96
              assert report['object_attention']['gaze_established_s']<report['object_attention']['reach_starts_s']
              assert report['hold_finger_adjustment_rad']>.005 and report['hold_load_travel_m']>.001
              assert report['min_hold_contacts']>=4
              assert set(report['acting_beats_s'])=={'commit','engage_lift','hold_assess','place_disengage'}
              hips=[];body=[];chest=[];held=[];heads=[]
              jacket=next(obj for obj in root.children_recursive if obj.get('lightek_source_object')=='Jacket body')
              for frame in range(1,97):
                  scene.frame_set(frame);bpy.context.view_layer.update()
                  hips.append(root.location.x);body.append(rig.pose.bones['Body'].matrix.translation.z);chest.append(jacket.scale.z);heads.append(rig.pose.bones['Head'].matrix.to_quaternion())
                  if 37<=frame<=54:held.append(prop.matrix_world.translation.copy())
              assert max(hips)-min(hips)>.004 and max(body)-min(body)>.02
              assert max(chest)-min(chest)>.001
              assert all((a-b).length>.00001 for a,b in zip(held,held[1:])),held
              assert heads[-1].rotation_difference(heads[60]).angle>.2
              assert bpy.data.objects['Articulated contact hand'].animation_data
              # Camera changes must not re-start acting or alter world poses.
              scene.frame_set(40);bpy.context.view_layer.update()
              baseline=[bone.matrix.copy() for bone in rig.pose.bones]
              for camera in [obj for obj in scene.objects if obj.type=='CAMERA']:
                  scene.camera=camera;bpy.context.view_layer.update()
                  assert all(max(abs(a-b) for ra,rb in zip(matrix,bone.matrix) for a,b in zip(ra,rb))<1e-7 for matrix,bone in zip(baseline,rig.pose.bones))
              assert report['pedestal_contact']['condim']==6

          assert 'Lightek contact simulation.json' in bpy.data.texts
          assert any(sound.packed_file for sound in bpy.data.sounds)
          print('ARTICULATED_CONTACT_GRASP_VERIFIED',report)
        PYTHON
        output=Studio::MediaProcess.run!([ENV.fetch("BLENDER_BIN","blender"),"--background","--disable-autoexec",file.path,"--python-exit-code","1","--python",script],timeout:60)
        assert_includes output,"ARTICULATED_CONTACT_GRASP_VERIFIED"
      end
      counts=[StudioAsset.count,SceneObject.count,StudioOperation.count];frozen=actor.definition["mechanics_plan"].deep_dup
      parent.update!(status:"failed");action("character_scene_retry",operation_id:parent.id);StudioCharacterSceneJob.perform_now(parent.id)
      assert_equal "completed",parent.reload.status
      assert_equal counts,[StudioAsset.count,SceneObject.count,StudioOperation.count]
      assert_equal frozen,actor.reload.definition["mechanics_plan"]
      invalid=preview.reload.manifest.deep_dup
      invalid.fetch("scene").fetch("objects").find { |row| row.dig("definition","mechanics_plan") }.fetch("definition").fetch("mechanics_plan")["physical_profile"]["prop_mass_kg"]=999
      preview.update!(manifest:invalid,status:"pending")
      error=assert_raises(Blender::Runner::ExecutionError) { StudioBlenderPreviewJob.perform_now(preview.id) }
      assert_includes error.message,"pinned contact physics implementation or profile changed"
    end
  ensure
    ENV["BLENDER_OUTPUT_ROOT"]=previous if defined?(previous)
  end
end
