require_relative "studio_lip_sync_checks"
require File.join(ROOT,"app/services/screenplay_engine/neural_voice")
require File.join(ROOT,"app/services/screenplay_engine/audio_synthesizer")
require File.join(ROOT,"app/services/studio/native_blender/media_presets")
require File.join(ROOT,"app/services/studio/native_blender/preset_use")
require File.join(ROOT,"app/services/studio/performance/scene_templates")
require File.join(ROOT,"app/services/studio/performance/character_scene")
require File.join(ROOT,"app/services/studio/performance/dialogue_scene")
require File.join(ROOT,"app/jobs/studio_character_scene_job")
class StudioCharacterSceneTest < StudioLipSyncTest
  StudioLipSyncTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def prepare(**values)
    action("character_scene_prepare",scene_id:@scene.id,name:"Sentinel",dialogue:"We protect this city.",request_key:"performed-short-123",**values)
  end
  def test_character_request_is_scoped_bounded_idempotent_and_reusable_cast_is_checked
    first=prepare
    assert_equal first,prepare
    assert_equal first,action("character_scene_status",scene_id:@scene.id)
    assert_equal 1,@project.studio_operations.where(capability:Studio::Performance::CharacterScene::CAPABILITY).count
    assert_raises(ArgumentError) { prepare(dialogue:"Different line") }
    assert_raises(ActiveRecord::RecordNotFound) { prepare(user_id:@bob.id) }
    assert_raises(ArgumentError) { prepare(name:"") }
    assert_raises(ArgumentError) { prepare(voice:"shell") }
    assert_raises(ArgumentError) { prepare(skin:"file:///etc/passwd") }
    assert_raises(ActiveRecord::RecordNotFound) { action("character_scene_status",operation_id:first[:operation_id],user_id:@bob.id) }
    assert_raises(ArgumentError) { action("character_scene_quote",operation_id:first[:operation_id]) }
    op=StudioOperation.find(first[:operation_id]);op.update!(status:"failed")
    action("character_scene_retry",operation_id:op.id)
    assert_equal 1,op.reload.metadata["attempt"]
    assert_raises(ArgumentError) { action("character_scene_retry",operation_id:op.id) }
  end
  def test_recording_is_frozen_and_template_copies_remap_camera_cuts
    audio=recording;original=audio.file.blob
    parent=StudioOperation.find(prepare(dialogue:"",audio_asset_id:audio.id)[:operation_id])
    audio.file.attach(io:StringIO.new("changed source"),filename:"changed.wav",content_type:"audio/wav",identify:false)
    assert_equal original.id,parent.manifest.dig("inputs","audio_blob_id")
    assert_includes parent.performance_sources.blobs.map(&:id),original.id
    refute_includes parent.performance_sources.blobs.map(&:id),audio.file.blob.id
    wide=@scene.scene_objects.create!(name:"Wide",object_type:"camera",definition:{location:[0,-5,1]})
    close=@scene.scene_objects.create!(name:"Close",object_type:"camera",definition:{location:[0,-5,1]})
    @scene.update!(settings:@scene.settings.merge("camera_cuts"=>[{"camera_id"=>wide.id,"frame"=>1},{"camera_id"=>close.id,"frame"=>19}]))
    template=action("template_save",project_id:@project.id,name:"Character show",request_key:SecureRandom.uuid)
    episode=action("template_use",project_id:template[:project_id],name:"Episode two",request_key:SecureRandom.uuid)
    copied=StudioScene.find(episode[:scene_id])
    ids=copied.settings.fetch("camera_cuts").map { |cut| cut.fetch("camera_id") }
    assert_equal copied.scene_objects.where(object_type:"camera").pluck(:id),ids
    refute_includes ids,wide.id
    assert_equal [1,19],copied.settings["camera_cuts"].map { |cut| cut["frame"] }
  end
  def test_real_illustrated_character_speech_pose_cut_and_editable_source
    skip "Set LIGHTEK_TEST_CHARACTER_SCENE=1 with speech and Blender tools" unless ENV["LIGHTEK_TEST_CHARACTER_SCENE"]=="1"
    previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=Dir.mktmpdir("performed-short-output-")
    Rails.stub(:root,Pathname(ROOT)) do
      parent=StudioOperation.find(prepare[:operation_id])
      StudioCharacterSceneJob.perform_now(parent.id)
      assert_equal "completed",parent.reload.status,parent.error_message
      result=action("character_scene_status",operation_id:parent.id)
      assert result[:url]
      character=StudioAsset.find(result[:cast_asset_id]);assert_equal "illustrated",character.metadata.dig("performer_build","style")
      assert character.metadata["character_profile"]["bindings"]["viseme_a"]
      target=StudioScene.find(result[:scene_id]);refute_equal @scene.id,target.id
      assert_equal 2,target.settings["camera_cuts"].length
      object=target.scene_objects.find { |item| item.definition["performance"] }
      assert_equal "phoneme",object.definition.dig("performance","lip_sync_mode")
      assert object.definition.dig("performance","lip_sync","cues").map { |cue| cue["value"] }.uniq.length>1
      child=StudioOperation.find(result[:preview_operation_id])
      assert child.metadata["draft_preview"]
      video=child.artifacts.find_by!(kind:"video")
      video.file.blob.open do |file|
        info=JSON.parse(IO.popen(["ffprobe","-v","error","-show_streams","-show_format","-of","json",file.path],&:read))
        assert_in_delta 3,info["format"]["duration"].to_f,0.1
        assert info["streams"].any? { |stream| stream["codec_type"]=="audio" }
        assert_operator File.size(file.path),:>,10000
        samples=IO.popen(["ffmpeg","-v","error","-i",file.path,"-vn","-ac","1","-ar","8000","-f","s16le","-"],"rb",&:read).unpack("s<*")
        assert samples.any? { |sample| sample.abs>500 },"Exported dialogue must be audible"
        FileUtils.cp(file.path,ENV["STUDIO_CHARACTER_PROOF_VIDEO"]) if ENV["STUDIO_CHARACTER_PROOF_VIDEO"]
      end
      blend=child.artifacts.find_by!(kind:"blend")
      blend.file.blob.open do |file|
        script=File.join(Dir.mktmpdir,"verify-character.py")
        File.write(script,<<~PYTHON)
          import bpy
          scene=bpy.context.scene
          assert len([m for m in scene.timeline_markers if m.camera])==2, [(m.name,m.frame,bool(m.camera)) for m in scene.timeline_markers]
          assert scene.timeline_markers[0].camera.data.type=='ORTHO'
          assert any(obj.type=='ARMATURE' for obj in scene.objects)
          assert any(sound.packed_file for sound in bpy.data.sounds)
          meshes=[obj for obj in scene.objects if obj.type=='MESH' and obj.data.shape_keys]
          assert any('viseme_d' in obj.data.shape_keys.key_blocks for obj in meshes)
          rigs=[obj for obj in bpy.data.objects if obj.type=='ARMATURE' and obj.animation_data]
          assert rigs
          poses=[];mouths=[]
          for frame in range(1,25):
              scene.frame_set(frame)
              poses.append(tuple(round(v,4) for v in rigs[0].pose.bones['Arm.R'].rotation_euler))
              mouths.append(tuple(round(key.value,4) for obj in meshes for key in obj.data.shape_keys.key_blocks if key.name.startswith('viseme_')))
          assert len(set(poses))>1
          assert len(set(mouths))>1
          scene.frame_set(1);wide=scene.camera;scene.frame_set(25)
          assert scene.camera!=wide
          print('CHARACTER_SCENE_EDITABLE')
        PYTHON
        output=Studio::MediaProcess.run!([ENV.fetch("BLENDER_BIN","blender"),"--background","--disable-autoexec",file.path,"--python-exit-code","1","--python",script],timeout:60)
        assert_includes output,"CHARACTER_SCENE_EDITABLE"
        FileUtils.cp(file.path,ENV["STUDIO_CHARACTER_PROOF_BLEND"]) if ENV["STUDIO_CHARACTER_PROOF_BLEND"]
      end
      counts=[StudioAsset.count,StudioScene.count,SceneObject.count,StudioOperation.where(operation_type:"speech_analysis").count]
      parent.update!(status:"failed")
      action("character_scene_retry",operation_id:parent.id)
      StudioCharacterSceneJob.perform_now(parent.id)
      assert_equal "completed",parent.reload.status
      assert_equal counts,[StudioAsset.count,StudioScene.count,SceneObject.count,StudioOperation.where(operation_type:"speech_analysis").count]
      quote=Studio::Billing::Quote.stub(:call,->(operation:,**_) { operation.update!(cost_quote:{"total_cents"=>550},status:"awaiting_payment") }) { action("character_scene_quote",operation_id:parent.id) }
      assert_equal "awaiting_payment",quote[:status]
      assert_equal quote,action("character_scene_quote",operation_id:parent.id)
      assert_empty @scene.scene_objects
    end
  ensure
    ENV["BLENDER_OUTPUT_ROOT"]=previous if defined?(previous)
  end
end
