require_relative "studio_directional_checks"
class StudioAttentionTest < StudioDirectionalTest
  instance_methods.grep(/^test_/).each { |method| undef_method(method) }
  def test_focal_points_are_scoped_finite_and_explicit
    result=bench(attention:{kind:"camera",start:3.25,end:6.4});assert_equal "camera",result.dig(:inputs,"attention","kind")
    assert_raises(ArgumentError) { bench(attention:{kind:"partner"}) }
    assert_raises(ArgumentError) { bench(attention:{kind:"object",target_id:"foreign"}) }
    assert_raises(ArgumentError) { bench(attention:{kind:"camera",target_id:"anything"}) }
    assert_raises(ArgumentError) { bench(attention:{kind:"camera",start:Float::NAN}) }
    assert_raises(ArgumentError) { bench(attention:{kind:"camera",start:3,end:2}) }
    StudioOperation.find(result[:operation_id]).update!(status:"failed")
    dialogue_result=dialogue(characters:[{name:"A",attention:{kind:"partner"}},{name:"B",attention:{kind:"camera"}}])
    assert_equal "partner",dialogue_result.dig(:inputs,"characters",0,"attention","kind")
    legacy=ready_actor
    assert_raises(ArgumentError) { Studio::Performance::Attention.validate_profile!({"attention"=>{"kind"=>"camera"}},legacy.metadata["character_profile"]) }
    raw=legacy.metadata["character_profile"].deep_dup;head=raw.fetch("bones").fetch("head")
    raw["attention_binding"]={"rig"=>head["object"],"head"=>head["bone"],"eye_anchor"=>[0,0,Float::NAN]}
    assert_raises(ArgumentError) { Studio::Performance::Cast.profile(legacy,raw) }
    assert_empty @scene.scene_objects
  end
  def test_real_partner_attention_is_head_only_bounded_and_restores_front_drawing
    skip "Set LIGHTEK_TEST_CHARACTER_SCENE=1" unless ENV["LIGHTEK_TEST_CHARACTER_SCENE"]=="1"
    previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=Dir.mktmpdir("partner-focus-")
    Rails.stub(:root,Pathname(ROOT)) do
      result=dialogue(characters:[{name:"Sentinel",attention:{kind:"partner",start:0,end:1.5}},{name:"Beacon",attention:{kind:"camera",start:0,end:4}}],turns:[{speaker:0,dialogue:"Look at me."},{speaker:1,dialogue:"I see you."}])
      parent=StudioOperation.find(result[:operation_id]);StudioCharacterSceneJob.perform_now(parent.id)
      assert_equal "completed",parent.reload.status,parent.error_message
      preview=StudioOperation.find(parent.metadata["preview_id"])
      preview.artifacts.find_by!(kind:"video").file.blob.open { |file| FileUtils.cp(file.path,ENV["STUDIO_PARTNER_PROOF_VIDEO"]) if ENV["STUDIO_PARTNER_PROOF_VIDEO"] }
      preview.artifacts.find_by!(kind:"blend").file.blob.open do |file|
        script=File.join(Dir.mktmpdir,"verify-partner.py")
        File.write(script,<<~PYTHON)
          import bpy,json
          scene=bpy.context.scene;a=bpy.data.objects['Sentinel'];b=bpy.data.objects['Beacon']
          first=json.loads(a['lightek_attention_report']);second=json.loads(b['lightek_attention_report'])
          assert first['kind']=='object' and first['clamped_frames']>0,first
          assert second['kind']=='camera' and second['max_aim_error_degrees']<.1,second
          for frame in range(1,scene.frame_end+1):
              scene.frame_set(frame)
              assert abs(a.rotation_euler.z-0.1745329252)<.0001 and abs(b.rotation_euler.z+0.1745329252)<.0001
              assert abs(a.rotation_euler.x)+abs(a.rotation_euler.y)+abs(b.rotation_euler.x)+abs(b.rotation_euler.y)<.0001
          mouth=next(obj for obj in a.children_recursive if obj.get('lightek_source_object')=='FaceMouth')
          profile_mouth=next(obj for obj in a.children_recursive if obj.get('lightek_source_object')=='Side FaceMouth')
          values=[]
          for frame in range(1,19):
              scene.frame_set(frame)
              sample=[]
              for key in profile_mouth.data.shape_keys.key_blocks:
                  if key.name.startswith('viseme_'):
                      assert abs(key.value-mouth.data.shape_keys.key_blocks[key.name].value)<.00001
                      sample.append(round(key.value,3))
              values.append(tuple(sample))
          assert len(set(values))>2
          scene.frame_set(scene.frame_end)
          front=next(obj for obj in a.children_recursive if obj.get('lightek_source_object')=='Head')
          side=next(obj for obj in a.children_recursive if obj.get('lightek_source_object')=='Side Head')
          assert not front.hide_render and side.hide_render
          print('PARTNER_HEAD_LIMITS_AND_RESTORATION_VERIFIED')
        PYTHON
        output=Studio::MediaProcess.run!([ENV.fetch("BLENDER_BIN","blender"),"--background","--disable-autoexec",file.path,"--python-exit-code","1","--python",script],timeout:60)
        assert_includes output,"PARTNER_HEAD_LIMITS_AND_RESTORATION_VERIFIED"
      end
    end
  ensure
    ENV["BLENDER_OUTPUT_ROOT"]=previous if defined?(previous)
  end
  def test_real_side_approach_then_fourth_wall_head_attention_without_turning_body
    skip "Set LIGHTEK_TEST_CHARACTER_SCENE=1" unless ENV["LIGHTEK_TEST_CHARACTER_SCENE"]=="1"
    previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=Dir.mktmpdir("attention-proof-")
    Rails.stub(:root,Pathname(ROOT)) do
      parent=StudioOperation.find(bench(attention:{kind:"camera",start:3.25,end:6.4})[:operation_id]);StudioCharacterSceneJob.perform_now(parent.id)
      assert_equal "completed",parent.reload.status,parent.error_message
      scene=StudioScene.find(parent.metadata["scene_id"]);actor=scene.scene_objects.find { |row| row.definition["attention_plan"] }
      assert_equal 2,actor.definition.dig("mechanics_plan","version")
      assert_equal "camera",actor.definition.dig("attention_plan","kind")
      preview=StudioOperation.find(parent.metadata["preview_id"])
      preview.artifacts.find_by!(kind:"video").file.blob.open { |file| FileUtils.cp(file.path,ENV["STUDIO_ATTENTION_PROOF_VIDEO"]) if ENV["STUDIO_ATTENTION_PROOF_VIDEO"] }
      preview.artifacts.find_by!(kind:"blend").file.blob.open do |file|
        script=File.join(Dir.mktmpdir,"verify-attention.py")
        File.write(script,<<~PYTHON)
          import bpy,json,sys
          from mathutils import Vector
          scene=bpy.context.scene;root=bpy.data.objects['Sentinel'];rig=next(obj for obj in root.children_recursive if obj.type=='ARMATURE');head=rig.pose.bones['Head']
          report=json.loads(root['lightek_attention_report']);assert report['frames']>20 and report['clamped_frames']==0 and report['max_aim_error_degrees']<.1,report
          front=next(obj for obj in root.children_recursive if obj.get('lightek_source_object')=='Head');side=next(obj for obj in root.children_recursive if obj.get('lightek_source_object')=='Side Head')
          scene.frame_set(1);assert front.hide_render and not side.hide_render
          assert (root.rotation_quaternion @ Vector((0,-1,0))).dot(Vector((1,0,0)))>.999
          for frame in range(42,76):
              scene.frame_set(frame)
              assert (root.rotation_quaternion @ Vector((0,-1,0))).dot(Vector((0,-1,0)))>.999
              eye=rig.matrix_world @ head.matrix @ head.bone.matrix_local.inverted() @ Vector((0,-.317,1.99))
              axis=head.bone.matrix_local.to_quaternion().inverted() @ Vector((0,-1,0));facing=rig.matrix_world.to_quaternion() @ head.matrix.to_quaternion() @ axis
              assert facing.dot((scene.camera.matrix_world.translation-eye).normalized())>.999
              assert not front.hide_render and side.hide_render
          sys.path.insert(0,#{File.join(ROOT,'blender').inspect})
          import spatial_frame_v1
          for normal,forward in [((0,0,1),(0,1,0)),((0,0,-1),(0,1,0)),((1,0,0),(0,1,0)),((-1,0,0),(0,1,0)),((0,1,0),(1,0,0)),((0,-1,0),(1,0,0))]:
              matrix=spatial_frame_v1.frame((2,3,4),normal,forward)
              assert abs(matrix.to_3x3().determinant()-1)<.00001
              assert (matrix.to_3x3() @ Vector((0,0,1))-Vector(normal)).length<.00001
              assert (matrix.inverted() @ (matrix @ Vector((.2,.3,.4)))-Vector((.2,.3,.4))).length<.00001
          print('SIDE_WALK_CAMERA_ATTENTION_AND_SURFACE_FRAMES_VERIFIED')
        PYTHON
        output=Studio::MediaProcess.run!([ENV.fetch("BLENDER_BIN","blender"),"--background","--disable-autoexec",file.path,"--python-exit-code","1","--python",script],timeout:60)
        assert_includes output,"SIDE_WALK_CAMERA_ATTENTION_AND_SURFACE_FRAMES_VERIFIED"
      end
    end
  ensure
    ENV["BLENDER_OUTPUT_ROOT"]=previous if defined?(previous)
  end
end
