# frozen_string_literal: true
require_relative "studio_authoring_checks"
require File.join(ROOT,"app/services/studio/performance/cast")
require File.join(ROOT,"app/services/studio/performance/audio_envelope")
require File.join(ROOT,"app/services/studio/performance/take")
require File.join(ROOT,"app/jobs/studio_character_create_job")
require File.join(ROOT,"app/jobs/studio_blender_preview_job")
require File.join(ROOT,"app/services/studio/workers/scene_object_mutation")
class StudioPerformanceTest < StudioAuthoringTest
  StudioAuthoringTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def ready_actor
    asset=StudioAsset.new(owner:@alice,site:@site,name:"Performer",kind:"blend",status:"ready",request_key:SecureRandom.uuid,
      metadata:{"scenes"=>[{"name"=>"Cast","objects"=>[{"name"=>"Face","definition"=>{"native_type"=>"MESH","shape_keys"=>[{"name"=>"Basis"},{"name"=>"Open"},{"name"=>"Smile"}]}},{"name"=>"Rig","definition"=>{"native_type"=>"ARMATURE","bones"=>[{"name"=>"Head"}]}}]}]})
    asset.file.attach(io:StringIO.new("source"),filename:"actor.blend",content_type:"application/x-blender",identify:false);asset.native.attach(asset.file.blob);asset.save!
    result=action("cast_register",asset_id:asset.id,name:"Reusable",profile:{source_scene:"Cast",bindings:{jaw_open:{object:"Face",key:"Open"},smile:{object:"Face",key:"Smile"}},bones:{head:{object:"Rig",bone:"Head"}}},request_key:SecureRandom.uuid)
    StudioAsset.find(result[:asset_id])
  end
  def placed_actor
    @actor||=ready_actor
    result=action("cast_place",asset_id:@actor.id,scene_id:@scene.id,lock_version:@scene.reload.lock_version,request_key:SecureRandom.uuid)
    SceneObject.find(result["object_id"])
  end
  def recording
    @recording||=Dir.mktmpdir("voice-fixture-") do |root|
      path=File.join(root,"voice.wav")
      Studio::MediaProcess.run!(["ffmpeg","-v","error","-y","-f","lavfi","-i","sine=frequency=180:duration=0.5","-f","lavfi","-i","anullsrc=r=8000:cl=mono:d=0.5","-filter_complex","[0:a][1:a]concat=n=2:v=0:a=1","-ac","1","-ar","8000",path])
      asset=StudioAsset.new(owner:@alice,site:@site,name:"Dialogue",kind:"audio",status:"ready",request_key:SecureRandom.uuid,metadata:{"duration"=>1,"has_audio"=>true})
      asset.file.attach(io:File.open(path),filename:"dialogue.wav",content_type:"audio/wav",identify:false);asset.save!;asset
    end
  end
  def save_take(object,**values)
    action("performance_save",scene_id:@scene.id,object_id:object.id,lock_version:@scene.reload.lock_version,audio_asset_id:recording.id,source_in:0,source_out:1,start:0,request_key:SecureRandom.uuid,**values)
  end
  def test_performance_cast_registration_placement_and_native_sources_are_reusable
    actor=ready_actor
    assert actor.metadata["character_profile"]
    key=SecureRandom.uuid
    args={asset_id:actor.id,scene_id:@scene.id,lock_version:@scene.lock_version,request_key:key}
    first=action("cast_place",**args);assert_equal first,action("cast_place",**args)
    second=action("cast_place",**args.merge(lock_version:@scene.reload.lock_version,request_key:SecureRandom.uuid))
    refute_equal first["object_id"],second["object_id"]
    assert_equal actor.native.blob.id,SceneObject.find(first["object_id"]).definition.dig("character_profile","source_blob_id")
    assert_equal 1,@scene.scene_objects.where(object_type:"camera").count
    assert_raises(ArgumentError) { Studio::Performance::Cast.profile(actor,{"source_scene"=>"Cast","bindings"=>{"jaw_open"=>{"object"=>"Face","key"=>"Missing"}}}) }
  end
  def test_performance_save_analyzes_audio_keeps_silence_and_preserves_the_character
    object=placed_actor;blob_id=@actor.native.blob.id
    result=save_take(object,expressions:[{control:"smile",start:0.1,end:0.8,value:0.7}],gestures:[{kind:"nod",start:0,end:1,strength:0.4}])
    take=object.reload.definition["performance"]
    assert_equal 1,take["duration"]
    assert take["mouth_frames"].first(10).any? { |sample|sample["value"]>0.5 }
    assert take["mouth_frames"].last(8).all? { |sample|sample["value"]==0 }
    assert_equal 1,take["expressions"].length;assert_equal 1,take["gestures"].length
    assert_equal blob_id,@actor.reload.native.blob.id
    key=take["take_id"]
    assert_equal result,save_take(object,request_key:key,expressions:[{control:"smile",start:0.1,end:0.8,value:0.7}],gestures:[{kind:"nod",start:0,end:1,strength:0.4}])
    assert_raises(ArgumentError){save_take(object,request_key:key,start:0.2)}
  end
  def test_performance_rejects_foreign_assets_bad_timing_unknown_controls_and_stale_writes
    object=placed_actor
    assert_raises(ArgumentError){save_take(object,source_out:31)}
    assert_raises(ArgumentError){save_take(object,expressions:[{control:"execute_python",start:0,end:1,value:1}])}
    assert_raises(ArgumentError){save_take(object,expressions:[{control:"smile",start:0,end:0.8},{control:"smile",start:0.5,end:1}])}
    assert_raises(ArgumentError){save_take(object,lock_version:0)}
    @alice.update!(role:"member")
    recording.update!(owner:@bob,site:@other_site)
    assert_raises(ActiveRecord::RecordNotFound){save_take(object)}
    assert_nil object.reload.definition["performance"]
  end
  def test_performance_operations_pin_sources_and_preview_is_bounded
    object=placed_actor;save_take(object)
    result=action("performance_preview",scene_id:@scene.id)
    op=StudioOperation.find(result[:operation_id]);assert_equal 2,op.performance_sources.count
    assert_equal op.id,action("performance_preview",scene_id:@scene.id)[:operation_id]
    assert op.manifest.dig("outputs","animation")
    assert op.manifest.dig("scene","settings","resolution_x")<=320
    assert op.manifest.dig("scene","settings","frame_end")<=72
    assert_equal 180,Blender::Runner.new(op).send(:timeout_seconds)
    action("performance_remove",scene_id:@scene.id,object_id:object.id,lock_version:@scene.reload.lock_version)
    assert action("performance_preview",scene_id:@scene.id,operation_id:op.id)[:stale]
    assert_nil object.reload.definition["performance"]
    assert op.reload.manifest.dig("scene","objects").any? { |item|item.dig("definition","performance") }
  end
  def test_performance_builtin_creation_idempotency_and_failed_validation
    key=SecureRandom.uuid
    first=action("cast_create",name:"Marlon's performer",skin:"#925e43",wardrobe:"#64388b",hair:"#211916",request_key:key)
    assert_equal first,action("cast_create",name:"Marlon's performer",skin:"#925e43",wardrobe:"#64388b",hair:"#211916",request_key:key)
    assert_equal "processing",StudioAsset.find(first[:asset_id]).status
    assert_raises(ArgumentError){action("cast_create",skin:"ruby:execute",request_key:SecureRandom.uuid)}
  end
  def test_performance_failed_build_can_be_retried_and_build_queue_is_bounded
    result=action("cast_create",name:"Retry",request_key:SecureRandom.uuid)
    asset=StudioAsset.find(result[:asset_id]);asset.update!(status:"failed",error_message:"Temporary worker failure")
    retried=action("cast_retry",asset_id:asset.id);assert_equal "processing",retried[:status]
    assert_nil asset.reload.error_message
    assert_raises(ArgumentError){action("cast_retry",asset_id:asset.id)}
    3.times { action("cast_create",request_key:SecureRandom.uuid) }
    assert_raises(ArgumentError){action("cast_create",request_key:SecureRandom.uuid)}
  end
  def test_performance_foreign_cast_and_foreign_project_are_rejected
    actor=ready_actor
    @alice.update!(role:"member")
    actor.update!(owner:@bob,site:@other_site)
    assert_raises(ActiveRecord::RecordNotFound){action("cast_place",asset_id:actor.id,scene_id:@scene.id,lock_version:@scene.lock_version,request_key:SecureRandom.uuid)}
    assert_raises(ActiveRecord::RecordNotFound){action("cast_register",asset_id:actor.id,profile:{},request_key:SecureRandom.uuid)}
    actor.update!(owner:@alice,site:@site)
    foreign=StudioProject.create!(owner:@bob,site:@other_site,name:"Private").studio_scenes.first
    assert_raises(ActiveRecord::RecordNotFound){action("cast_place",asset_id:actor.id,scene_id:foreign.id,lock_version:0,request_key:SecureRandom.uuid)}
  end
  def test_performance_cast_browser_sends_bindings_without_mesh_or_graph_samples
    actor=ready_actor
    scenes=actor.metadata["scenes"].deep_dup
    scenes[0]["objects"][0]["definition"]["mesh"]={"vertices"=>[[1,2,3]]}
    scenes[0]["objects"][0]["definition"]["graphs"]=[{"nodes"=>[1,2,3]}]
    actor.update!(metadata:actor.metadata.merge("scenes"=>scenes))
    record=action("assets_list",surface:"performance")[:assets].find { |item| item[:id]==actor.id }
    shape=record[:metadata]["scenes"][0]["objects"][0]["definition"]
    assert shape["shape_keys"].any?;refute shape.key?("mesh");refute shape.key?("graphs")
    assert_equal actor.metadata["character_profile"],record[:metadata]["character_profile"]
  end
  def test_performance_dashboard_lists_productions_cast_and_embeds_authorized_workspace
    actor=ready_actor
    client=session_for
    client.get "/dashboard/studio-broadcasting",headers:headers.merge("Accept"=>"text/html")
    assert_equal 200,client.response.status,client.response.body
    assert_includes client.response.body,"Shows & episodes"
    assert_includes client.response.body,actor.name
    client.get "/dashboard/studio-broadcasting/workspace/#{@scene.id}",params:{workspace:"performance"},headers:headers.merge("Accept"=>"text/html")
    assert_equal 200,client.response.status,client.response.body
    assert_includes client.response.body,"<iframe"
    assert_includes client.response.body,"/lightek/index.html?workspace=performance#/studio/#{@scene.id}"
    foreign=StudioProject.create!(owner:@bob,site:@other_site,name:"Private").studio_scenes.first
    client.get "/dashboard/studio-broadcasting/workspace/#{foreign.id}",headers:headers.merge("Accept"=>"text/html")
    assert_equal 404,client.response.status
  end
  def test_performance_generic_object_mutations_cannot_inject_character_bindings_or_takes
    assert_raises(ArgumentError) { Studio::Workers::SceneObjectMutation.perform("create",user_id:@alice.id,site_id:@site.id,scene_id:@scene.id,name:"Spoof",object_type:"imported_asset",definition:{performance:{audio_path:"/etc/passwd"}}) }
    assert_raises(ArgumentError) { Studio::Workers::SceneObjectMutation.perform("transform",user_id:@alice.id,site_id:@site.id,scene_id:@scene.id,object_id:123,attributes:{definition:{character_profile:{source_blob_id:123}}}) }
    assert_equal 0,@scene.scene_objects.count
  end
  def test_performance_episode_copies_preserve_cast_and_keep_direction_independent
    object=placed_actor;save_take(object)
    source=object.reload.definition.deep_dup
    template=action("template_save",project_id:@project.id,name:"My show",request_key:SecureRandom.uuid)
    episode=action("template_use",project_id:template[:project_id],name:"My show — Episode 2",request_key:SecureRandom.uuid)
    copy=StudioScene.find(episode[:scene_id]);project=copy.studio_project
    assert_equal "My show — Episode 2",project.name
    copied=copy.scene_objects.find_by!(object_type:"imported_asset")
    assert_equal source["character_profile"],copied.definition["character_profile"]
    assert_equal source["performance"],copied.definition["performance"]
    assert_nil copy.settings["cast_receipts"];assert_nil copy.settings["performance_receipts"]
    copied.update!(definition:copied.definition.except("performance"))
    assert_equal source["performance"],object.reload.definition["performance"]
  end
  def test_performance_real_native_character_animated_movie_and_audible_voice
    skip "Set LIGHTEK_TEST_BLENDER=1" unless ENV["LIGHTEK_TEST_BLENDER"]=="1"
    result=action("cast_create",name:"Lightek performer",request_key:SecureRandom.uuid)
    Rails.stub(:root,Pathname(ROOT)) { StudioCharacterCreateJob.perform_now(result[:asset_id]) }
    actor=StudioAsset.find(result[:asset_id]);assert_equal "ready",actor.status;assert actor.metadata["character_profile"]
    placed=action("cast_place",scene_id:@scene.id,asset_id:actor.id,lock_version:@scene.reload.lock_version,request_key:SecureRandom.uuid)
    object=SceneObject.find(placed["object_id"])
    second=action("cast_place",scene_id:@scene.id,asset_id:actor.id,lock_version:@scene.reload.lock_version,request_key:SecureRandom.uuid)
    SceneObject.find(second["object_id"]).update!(definition:object.definition.merge("location"=>[2,0,0]))
    save_take(object,source_in:0.25,source_out:1,start:0.125,expressions:[{control:"smile",start:0.1,end:0.7,value:0.8}],gestures:[{kind:"nod",start:0,end:0.75,strength:0.4}])
    @scene.reload.update!(settings:@scene.settings.merge("resolution_x"=>128,"resolution_y"=>128,"render_engine"=>"CYCLES","samples"=>1,"fps"=>8,"frame_start"=>1,"frame_end"=>8))
    manifest=Blender::ManifestBuilder.new(@scene).call;manifest["outputs"]={"blend"=>true,"animation"=>true}
    op=@project.studio_operations.create!(studio_scene:@scene,operation_type:"build_scene",provider:"blender",capability:"studio.render.preview",status:"pending",intent:{"user_id"=>@alice.id},manifest:manifest)
    recording.file.attach(io:StringIO.new("replacement after render was queued"),filename:"changed.wav",content_type:"audio/wav",identify:false)
    Dir.mktmpdir("performance-render-") do |root|
      old=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=root
      Rails.stub(:root,Pathname(ROOT)) do
        rendered=Studio::Providers::BlenderProvider.new(op).call
        movie=rendered.output_directory.join("movie.mp4").to_s
        probe=JSON.parse(Studio::MediaProcess.run!(["ffprobe","-v","error","-show_streams","-show_format","-of","json",movie]))
        assert probe["streams"].any? { |stream|stream["codec_type"]=="audio" }
        assert probe["streams"].any? { |stream|stream["codec_name"]=="h264" }
        assert_in_delta 1,probe["format"]["duration"].to_f,0.15
        samples=Studio::MediaProcess.run!(["ffmpeg","-v","error","-i",movie,"-vn","-f","s16le","-ac","1","-ar","8000","-"]).b.unpack("s<*")
        assert_operator samples.map(&:abs).max,:>,100
        pixels=Studio::MediaProcess.run!(["ffmpeg","-v","error","-i",movie,"-frames:v","1","-f","rawvideo","-pix_fmt","rgb24","-"]).b.bytes
        assert_operator pixels.sum.to_f/pixels.length,:>,10,"The movie must contain visible picture"
        hashes=Studio::MediaProcess.run!(["ffmpeg","-v","error","-i",movie,"-an","-f","framemd5","-"]).lines.reject{|line|line.start_with?("#")}.map{|line|line.split(",").last&.strip}.compact
        assert_operator hashes.uniq.length,:>,1,"The rendered performance must visibly animate"
        if ENV["STUDIO_PERFORMANCE_PROOF"]
          FileUtils.mkdir_p(ENV["STUDIO_PERFORMANCE_PROOF"])
          FileUtils.cp(movie,File.join(ENV["STUDIO_PERFORMANCE_PROOF"],"performance.mp4"))
          Studio::MediaProcess.run!(["ffmpeg","-v","error","-y","-i",movie,"-frames:v","1",File.join(ENV["STUDIO_PERFORMANCE_PROOF"],"frame.png")])
        end
        script="import bpy,json; s=bpy.context.scene; mouths=[o for o in s.objects if o.type=='MESH' and o.data.shape_keys and 'jaw_open' in o.data.shape_keys.key_blocks]; s.frame_set(2); print('PERFORMANCE_PROOF='+json.dumps({'mouths':[o.data.shape_keys.key_blocks['jaw_open'].value for o in mouths],'independent':mouths[0].data!=mouths[1].data,'packed':all(t.sound.packed_file is not None for t in s.sequence_editor.sequences if t.type=='SOUND'),'trim':[t.frame_final_start-t.frame_start for t in s.sequence_editor.sequences if t.type=='SOUND'],'animated':any(o.type=='ARMATURE' and o.animation_data for o in s.objects)}))"
        output=Studio::MediaProcess.run!(["blender","--background",rendered.output_directory.join("scene.blend").to_s,"--disable-autoexec","--python-expr",script],timeout:60)
        proof=JSON.parse(output.lines.find{|line|line.start_with?("PERFORMANCE_PROOF=")}.delete_prefix("PERFORMANCE_PROOF="))
        assert_equal 2,proof["mouths"].length;assert proof["independent"];assert proof["mouths"].any? { |value|value>0.1 };assert proof["mouths"].any?(&:zero?);assert proof["packed"];assert proof["animated"];assert_equal [2],proof["trim"]
      end
    ensure
      ENV["BLENDER_OUTPUT_ROOT"]=old
    end
  end
end
