require_relative "studio_character_scene_checks"
class StudioDialogueSceneTest < StudioCharacterSceneTest
  StudioCharacterSceneTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def dialogue(**extra)
    action("character_scene_prepare",scene_id:@scene.id,mode:"dialogue",request_key:"dialogue-short-123",scene_template:"studio",
      characters:[{name:"Sentinel",voice:"en-us",wardrobe:"#344e78"},{name:"Beacon",voice:"en-gb",wardrobe:"#945228"}],
      turns:[{speaker:0,dialogue:"Stay alert."},{speaker:1,dialogue:"I am ready."}],**extra)
  end
  def test_dialogue_bounds_scope_request_identity_and_both_speakers
    result=dialogue
    assert_equal result,dialogue
    assert_equal "dialogue",result.dig(:inputs,"mode")
    assert_equal 2,result.dig(:inputs,"characters").size
    assert_equal result,action("character_scene_status",scene_id:@scene.id)
    assert_raises(ArgumentError) { dialogue(turns:[{speaker:0,dialogue:"Changed."},{speaker:1,dialogue:"Ready."}]) }
    assert_raises(ArgumentError) { dialogue(characters:[]) }
    assert_raises(ArgumentError) { dialogue(characters:[{name:"Same"},{name:"same"}]) }
    assert_raises(ArgumentError) { dialogue(turns:[{speaker:0,dialogue:"Line."},{speaker:0,dialogue:"Again."}]) }
    assert_raises(ArgumentError) { dialogue(turns:[{speaker:2,dialogue:"Line."},{speaker:1,dialogue:"Again."}]) }
    assert_raises(ArgumentError) { dialogue(turns:[{speaker:0,dialogue:""},{speaker:1,dialogue:"Again."}]) }
    assert_raises(ArgumentError) { dialogue(characters:[{name:"A",voice:"shell"},{name:"B"}]) }
    assert_raises(ActiveRecord::RecordNotFound) { action("character_scene_status",operation_id:result[:operation_id],user_id:@bob.id) }
    assert_raises(ActiveRecord::RecordNotFound) { dialogue(characters:[{name:"A",cast_asset_id:999999},{name:"B"}]) }
    assert_raises(ArgumentError) { action("performance_preview",scene_id:@scene.id,preview_seconds:9) }
  end
  def test_each_owned_recording_is_frozen_on_the_parent
    audio=recording;blob=audio.file.blob
    result=dialogue(turns:[{speaker:0,dialogue:"",audio_asset_id:audio.id},{speaker:1,dialogue:"",audio_asset_id:audio.id}])
    op=StudioOperation.find(result[:operation_id])
    audio.file.attach(io:StringIO.new("changed source"),filename:"changed.wav",content_type:"audio/wav",identify:false)
    assert_equal [blob.id,blob.id],op.manifest["inputs"]["turns"].map { |turn| turn["audio_blob_id"] }
    assert_equal [blob.id],op.performance_sources.blobs.map(&:id)
    assert_empty @scene.scene_objects
  end
  def test_manual_take_edits_clear_conflicting_listener_cues_and_remove_clears_reactions
    object=placed_actor
    object.update!(definition:object.definition.merge("listener_reactions"=>[{"kind"=>"listen","start"=>0.3,"duration"=>0.5,"speaker_object_id"=>object.id}]))
    save_take(object)
    assert_empty object.reload.definition["listener_reactions"]
    action("performance_remove",scene_id:@scene.id,object_id:object.id,lock_version:@scene.reload.lock_version)
    refute object.reload.definition.key?("listener_reactions")
  end
  def test_real_two_character_scene_has_separate_speech_reactions_and_camera_cuts
    skip "Set LIGHTEK_TEST_CHARACTER_SCENE=1 with native tools" unless ENV["LIGHTEK_TEST_CHARACTER_SCENE"]=="1"
    previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=Dir.mktmpdir("dialogue-output-")
    Rails.stub(:root,Pathname(ROOT)) do
      parent=StudioOperation.find(dialogue(turns:[{speaker:0,dialogue:"Stay alert."},{speaker:1,dialogue:"I am ready."},{speaker:0,dialogue:"Follow my lead."}])[:operation_id]);StudioCharacterSceneJob.perform_now(parent.id)
      assert_equal "completed",parent.reload.status,parent.error_message
      receipt=action("character_scene_status",operation_id:parent.id);assert receipt[:url]
      target=StudioScene.find(receipt[:scene_id]);refute_equal @scene.id,target.id
      cast=target.scene_objects.select { |object| object.definition["dialogue_initialized"] }
      assert_equal 2,cast.size
      assert_equal 2,cast.map { |object| object.definition["asset_id"] }.uniq.size
      assert_equal ["en-us","en-gb"],parent.manifest.dig("inputs","characters").map { |row| row["voice"] }
      takes=cast.flat_map { |object| object.definition["performance_takes"] }.sort_by { |take| take["start"] }
      assert_equal 3,takes.size
      assert_equal 3,takes.map { |take| take["audio_blob_id"] }.uniq.size
      assert_operator takes[1]["start"],:>,takes[0]["start"]+takes[0]["duration"]
      assert takes.all? { |take| take["lip_sync_mode"]=="phoneme" && take.dig("lip_sync","cues").size>1 }
      assert_equal 4,target.settings["camera_cuts"].size
      assert_equal 3,target.settings["camera_cuts"].map { |cut| cut["camera_id"] }.uniq.size
      assert_equal [1,2],cast.map { |object| object.definition["listener_reactions"].size }.sort
      child=StudioOperation.find(receipt[:preview_operation_id]);assert child.metadata["draft_preview"]
      assert_equal target.settings["frame_end"],child.manifest.dig("scene","settings","frame_end")
      child.artifacts.find_by!(kind:"video").file.blob.open do |file|
        info=JSON.parse(IO.popen(["ffprobe","-v","error","-show_streams","-show_format","-of","json",file.path],&:read))
        assert_in_delta target.settings["frame_end"]/12.0,info["format"]["duration"].to_f,0.1
        assert info["streams"].any? { |stream| stream["codec_type"]=="audio" }
        samples=IO.popen(["ffmpeg","-v","error","-i",file.path,"-vn","-ac","1","-ar","8000","-f","s16le","-"],"rb",&:read).unpack("s<*")
        takes.each do |take|
          first=((take["start"]+0.05)*8000).round;last=((take["start"]+take["duration"]-0.05)*8000).round
          assert samples[first..last].any? { |sample| sample.abs>500 },"Both exported speaking turns must be audible"
        end
        FileUtils.cp(file.path,ENV["STUDIO_DIALOGUE_PROOF_VIDEO"]) if ENV["STUDIO_DIALOGUE_PROOF_VIDEO"]
      end
      child.artifacts.find_by!(kind:"blend").file.blob.open do |file|
        script=File.join(Dir.mktmpdir,"verify-dialogue.py")
        File.write(script,<<~PYTHON)
          import bpy
          scene=bpy.context.scene
          assert len([m for m in scene.timeline_markers if m.camera])==4
          assert len([sound for sound in bpy.data.sounds if sound.packed_file])==3
          rigs=[obj for obj in scene.objects if obj.type=='ARMATURE']
          assert len(rigs)==2
          assert all(rig.animation_data for rig in rigs)
          faces=[obj for obj in scene.objects if obj.type=='MESH' and obj.data.shape_keys and 'brow_raise' in obj.data.shape_keys.key_blocks]
          assert len(faces)==2
          mouth_meshes=[obj for obj in scene.objects if obj.type=='MESH' and obj.data.shape_keys and any(key.name.startswith('viseme_') for key in obj.data.shape_keys.key_blocks)]
          assert len(mouth_meshes)==2
          reactions=[];mouths=[]
          for frame in range(1,scene.frame_end+1):
              scene.frame_set(frame)
              reactions.append(tuple(round(face.data.shape_keys.key_blocks['brow_raise'].value,3) for face in faces))
              mouths.append(tuple(round(key.value,3) for face in mouth_meshes for key in face.data.shape_keys.key_blocks if key.name.startswith('viseme_')))
          assert len(set(reactions))>2
          assert len(set(mouths))>2
          print('DIALOGUE_SOURCE_VERIFIED')
        PYTHON
        output=Studio::MediaProcess.run!([ENV.fetch("BLENDER_BIN","blender"),"--background","--disable-autoexec",file.path,"--python-exit-code","1","--python",script],timeout:60)
        assert_includes output,"DIALOGUE_SOURCE_VERIFIED"
        FileUtils.cp(file.path,ENV["STUDIO_DIALOGUE_PROOF_BLEND"]) if ENV["STUDIO_DIALOGUE_PROOF_BLEND"]
      end
      counts=[StudioAsset.count,StudioScene.count,SceneObject.count,StudioOperation.count]
      parent.update!(status:"failed");action("character_scene_retry",operation_id:parent.id);StudioCharacterSceneJob.perform_now(parent.id)
      assert_equal "completed",parent.reload.status
      assert_equal counts,[StudioAsset.count,StudioScene.count,SceneObject.count,StudioOperation.count]
      assert_empty @scene.scene_objects
      template=action("template_save",project_id:@project.id,name:"Dialogue show",request_key:SecureRandom.uuid)
      copied=StudioProject.find(template[:project_id]).studio_scenes.find_by!(name:target.name)
      copied_ids=copied.scene_objects.pluck(:id)
      copied.scene_objects.select { |object| object.definition["listener_reactions"] }.each do |object|
        object.definition["listener_reactions"].each { |cue| assert_includes copied_ids,cue["speaker_object_id"] }
      end
      snapshot=Studio::Performance::SceneTemplates.snapshot(access:Studio::PwaAccess.new("user_id"=>@alice.id,"site_id"=>@site.id),source:target,key:"current")
      refute snapshot["settings"].key?("dialogue_scene_cameras")
    end
  ensure
    ENV["BLENDER_OUTPUT_ROOT"]=previous if defined?(previous)
  end
end
