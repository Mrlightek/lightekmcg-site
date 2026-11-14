require_relative "studio_performance_checks"
require File.join(ROOT,"app/services/studio/performance/lip_sync")
require File.join(ROOT,"app/jobs/studio_lip_sync_job")
class StudioLipSyncTest < StudioPerformanceTest
  StudioPerformanceTest.instance_methods(false).grep(/^test_/).each{|method|undef_method(method)}
  def analyze(**extra)
    action("performance_analyze",scene_id:@scene.id,audio_asset_id:recording.id,source_in:0,source_out:1,recognizer:"phonetic",request_key:"speech-request-123",**extra)
  end
  def fixture_result
    {"engine"=>"rhubarb","version"=>"1.14.0","recognizer"=>"phonetic","duration"=>1,
      "cues"=>[{"start"=>0.0,"end"=>0.3,"value"=>"A"},{"start"=>0.3,"end"=>0.8,"value"=>"D"},{"start"=>0.8,"end"=>1.0,"value"=>"X"}]}
  end
  def complete(id)
    Studio::Performance::LipSync.stub(:call,fixture_result){StudioLipSyncJob.perform_now(id)}
  end
  def test_speech_queued_analysis_is_idempotent_pins_source_and_never_edits_scene
    first=analyze;assert_equal first,analyze
    operation=StudioOperation.find(first[:id]);assert_equal "pending",operation.status
    assert_equal recording.file.blob.id,operation.performance_sources.blobs.first.id
    version=@scene.reload.lock_version
    complete(operation.id)
    assert_equal version,@scene.reload.lock_version
    result=action("performance_analysis",scene_id:@scene.id,operation_id:operation.id)
    assert_equal "completed",result[:status];assert_equal 3,result[:result]["cues"].length
    refute action("operations_list",project_id:@project.id)[:operations].any?{|op|op[:id]==operation.id}
    assert_raises(ArgumentError){analyze(dialogue:"Different direction")}
    Studio::Performance::LipSync.stub(:call,->(*){raise "must not replay"}){StudioLipSyncJob.perform_now(operation.id)}
  end
  def test_speech_corrections_save_native_take_with_pinned_analysis_and_legacy_volume
    object=placed_actor;id=analyze[:id];complete(id)
    corrected=fixture_result["cues"].deep_dup;corrected[1]["value"]="F"
    save_take(object,lip_sync_mode:"phoneme",analysis_id:id,mouth_cues:corrected)
    take=object.reload.definition["performance"]
    assert_equal "phoneme",take["lip_sync_mode"];assert_empty take["mouth_frames"]
    assert_equal corrected,take.dig("lip_sync","cues");assert_equal id,take.dig("lip_sync","analysis_id")
    assert_equal recording.file.blob.id,take["audio_blob_id"]
    snapshot=Blender::ManifestBuilder.new(@scene.reload).call
    assert_equal corrected,snapshot.dig("scene","objects").find{|o|o["id"]==object.id}.dig("definition","performance","lip_sync","cues")
    save_take(object)
    assert_equal "volume",object.reload.definition.dig("performance","lip_sync_mode")
    assert object.definition.dig("performance","mouth_frames").any?
  end
  def test_speech_episode_can_refine_its_saved_cues_without_reanalyzing_source
    object=placed_actor;id=analyze[:id];complete(id)
    save_take(object,lip_sync_mode:"phoneme",analysis_id:id)
    template=action("template_save",project_id:@project.id,name:"Speaking show",request_key:SecureRandom.uuid)
    episode=action("template_use",project_id:template[:project_id],name:"Episode 2",request_key:SecureRandom.uuid)
    scene=StudioScene.find(episode[:scene_id]);copy=scene.scene_objects.find_by!(object_type:"imported_asset")
    corrected=fixture_result["cues"].deep_dup;corrected[1]["value"]="E"
    action("performance_save",scene_id:scene.id,object_id:copy.id,lock_version:scene.lock_version,audio_asset_id:recording.id,source_in:0,source_out:1,start:0,
      lip_sync_mode:"phoneme",analysis_id:id,mouth_cues:corrected,request_key:SecureRandom.uuid)
    assert_equal "E",copy.reload.definition.dig("performance","lip_sync","cues",1,"value")
    assert_equal "D",object.reload.definition.dig("performance","lip_sync","cues",1,"value")
  end
  def test_speech_rejects_stale_trim_pending_analysis_foreign_sources_and_overlapping_cues
    object=placed_actor;id=analyze[:id]
    assert_raises(ArgumentError){save_take(object,lip_sync_mode:"phoneme",analysis_id:id)}
    complete(id)
    assert_raises(ArgumentError){save_take(object,source_in:0.2,lip_sync_mode:"phoneme",analysis_id:id)}
    assert_raises(ArgumentError){save_take(object,lip_sync_mode:"phoneme",analysis_id:id,mouth_cues:[{"start"=>0,"end"=>0.5,"value"=>"D"},{"start"=>0.4,"end"=>1,"value"=>"F"}])}
    assert_raises(ArgumentError){analyze(recognizer:"execute",request_key:SecureRandom.uuid)}
    assert_raises(ArgumentError){analyze(source_out:31,request_key:SecureRandom.uuid)}
    @alice.update!(role:"member");recording.update!(owner:@bob,site:@other_site)
    assert_raises(ActiveRecord::RecordNotFound){analyze(request_key:SecureRandom.uuid)}
    assert_raises(ActiveRecord::RecordNotFound){action("performance_analysis",scene_id:@scene.id,operation_id:id,user_id:@bob.id,site_id:@other_site.id)}
  end
  def test_speech_engine_failure_and_interruption_are_explicit_and_retryable
    id=analyze[:id]
    Studio::Performance::LipSync.stub(:call,->(*){raise "private worker details"}) do
      assert_raises(RuntimeError){StudioLipSyncJob.perform_now(id)}
    end
    op=StudioOperation.find(id);assert_equal "failed",op.status;refute_includes op.error_message,"private worker details"
    next_id=analyze(request_key:SecureRandom.uuid)[:id]
    op=StudioOperation.find(next_id);op.update!(status:"running",started_at:6.minutes.ago)
    StudioLipSyncJob.perform_now(op.id)
    assert_equal "failed",op.reload.status
  end
  def test_speech_validator_rejects_invalid_times_shapes_sizes_and_nan
    [{"start"=>0,"end"=>1,"value"=>"Z"},{"start"=>Float::NAN,"end"=>1,"value"=>"A"},{"start"=>0,"end"=>2,"value"=>"A"}].each do |cue|
      assert_raises(ArgumentError){Studio::Performance::LipSync.cues([cue],duration:1)}
    end
    assert_raises(ArgumentError){Studio::Performance::LipSync.cues([],duration:1)}
    assert_raises(ArgumentError){Studio::Performance::LipSync.cues([{}]*1025,duration:1)}
  end
  def test_speech_wrong_engine_version_fails_before_analysis
    blob=recording.file.blob
    Studio::MediaProcess.stub(:run!,"Rhubarb Lip Sync version 0.0.0") do
      assert_raises(ArgumentError){Studio::Performance::LipSync.call(blob,first:0,duration:1,recognizer:"phonetic",dialogue:"")}
    end
  end
  def test_speech_real_offline_engine_decodes_recording_and_produces_multiple_shapes
    skip "Set LIGHTEK_RHUBARB to the pinned binary" unless ENV["LIGHTEK_RHUBARB"]
    path=File.join(Dir.tmpdir,"lightek-spoken-#{SecureRandom.hex(5)}.wav")
    Studio::MediaProcess.run!(["ffmpeg","-v","error","-y","-f","lavfi","-i","flite=text='Hello Lightek. We are making a movie today.':voice=slt","-ac","1","-ar","16000",path])
    bytes=File.binread(path);duration=JSON.parse(Studio::MediaProcess.run!(["ffprobe","-v","error","-show_format","-of","json",path])).dig("format","duration").to_f
    asset=StudioAsset.new(owner:@alice,site:@site,name:"Spoken fixture",kind:"audio",status:"ready",request_key:SecureRandom.uuid,metadata:{"duration"=>duration,"has_audio"=>true})
    asset.file.attach(io:StringIO.new(bytes),filename:"speech.wav",content_type:"audio/wav",identify:false);asset.save!
    id=analyze(audio_asset_id:asset.id,source_out:duration,request_key:SecureRandom.uuid)[:id]
    Rails.stub(:root,Pathname(ROOT)){StudioLipSyncJob.perform_now(id)}
    op=StudioOperation.find(id);assert_equal "completed",op.status
    cues=op.manifest.dig("lip_sync","cues");assert_operator cues.length,:>,5;assert_operator cues.map{|c|c["value"]}.uniq.length,:>,3
    assert_in_delta duration,cues.last["end"],0.02
  ensure
    FileUtils.rm_f(path) if path
  end
end
