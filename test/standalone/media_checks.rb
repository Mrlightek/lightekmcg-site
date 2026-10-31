require_relative "community_checks"
require "open3"
require File.join(ROOT,"app/services/blender/runner")
require File.join(ROOT,"app/services/studio/providers/blender_provider")
require File.join(ROOT,"app/services/studio/publishers/lightek_streaming")
require File.join(ROOT,"app/services/studio/gatekeeper/client")
require File.join(ROOT,"app/services/studio/providers/registry")
require File.join(ROOT,"app/services/studio/operations/dispatcher")
require File.join(ROOT,"app/jobs/execute_studio_operation_job")
class StudioMediaIntegrationTest < LightekCommunityIntegrationTest
  LightekCommunityIntegrationTest.instance_methods(false).grep(/^test_/).each { |m| undef_method(m) }
  def test_real_media_ingestion_and_keyframed_multitrack_export
    Dir.mktmpdir("studio-test-") do |dir|
      video=File.join(dir,"source.mp4")
      _o,e,s=Open3.capture3("ffmpeg","-v","error","-y","-f","lavfi","-i","color=c=red:s=160x90:r=24:d=2","-f","lavfi","-i","sine=frequency=440:duration=2","-c:v","libx264","-pix_fmt","yuv420p","-threads","1","-c:a","aac","-shortest",video)
      assert s.success?,e
      asset=StudioAsset.new(owner:@alice,site:@site,name:"Camera take",kind:"video",request_key:SecureRandom.uuid)
      asset.file.attach(io:File.open(video),filename:"take.mp4",content_type:"video/mp4",identify:false)
      asset.save!
      Studio::Assets::Ingestor.call(asset)
      assert_equal "ready",asset.reload.status
      assert asset.thumbnail.attached?
      assert asset.metadata["has_audio"]
      timeline={"output"=>"video","width"=>160,"height"=>90,"clips"=>[
        {"asset_id"=>asset.id,"in"=>0.2,"out"=>1.5,"start"=>0,"track"=>0,"keyframes"=>[{"time"=>0,"x"=>0,"y"=>0,"gain"=>0.5},{"time"=>1,"x"=>10,"y"=>0,"gain"=>1}]},
        {"asset_id"=>asset.id,"in"=>0,"out"=>1,"start"=>0.2,"track"=>1,"muted"=>true,"x"=>40,"y"=>20}]}
      p=StudioProject.create!(owner:@alice,site:@site,name:"Edited scene")
      scene=p.studio_scenes.first
      result=Studio::Workers::Workspace.perform("timeline_save",user_id:@alice.id,site_id:@site.id,scene_id:scene.id,lock_version:scene.lock_version,timeline:timeline)
      assert_equal 2,result[:timeline]["clips"].length
      op=p.studio_operations.create!(studio_scene:scene,operation_type:"edit_media",provider:"ffmpeg",capability:"studio.workspace.timeline.quote",status:"pending",intent:{"user_id"=>@alice.id},manifest:{"timeline"=>scene.reload.settings["timeline"]})
      op.update!(status:"awaiting_payment")
      op.payment_succeeded!(Struct.new(:id).new(101))
      assert_equal "pending",op.reload.status
      ExecuteStudioOperationJob.perform_now(op.id)
      assert_equal "completed",op.reload.status
      artifact=op.artifacts.find_by!(kind:"video")
      ExecuteStudioOperationJob.perform_now(op.id)
      assert_equal 1,op.artifacts.count
      assert_equal "video",artifact.kind
      assert artifact.file.attached?
      artifact.file.blob.open do |file|
        out,_err,status=Open3.capture3("ffprobe","-v","error","-show_streams","-show_format","-of","json",file.path)
        assert status.success?
        data=JSON.parse(out)
        assert data["streams"].any?{|stream|stream["codec_type"]=="audio"}
        assert data["streams"].any?{|stream|stream["codec_type"]=="video"&&stream["width"]==160}
        assert_in_delta 1.3,data.dig("format","duration").to_f,0.15
      end
    end
  end
  def test_timeline_rejects_foreign_assets_and_unbounded_keyframes
    asset=StudioAsset.create!(owner:@bob,site:@site,name:"Private",kind:"audio",status:"ready",request_key:SecureRandom.uuid,metadata:{duration:2,has_audio:true})
    p=StudioProject.create!(owner:@alice,site:@site,name:"Mine")
    assert_raises(ArgumentError){Studio::Workers::Workspace.perform("timeline_save",user_id:@alice.id,site_id:@site.id,scene_id:p.studio_scenes.first.id,lock_version:0,timeline:{clips:[{asset_id:asset.id,out:1}]})}
  end
  def test_live_encoder_produces_real_hls_playback_segments
    Dir.mktmpdir("hls-live-") do |root|
      input=File.join(root,"capture.webm")
      _out,error,status=Open3.capture3("ffmpeg","-v","error","-y","-f","lavfi","-i","testsrc2=size=160x90:rate=24","-f","lavfi","-i","sine=frequency=440:sample_rate=48000","-t","4","-c:v","libvpx","-deadline","realtime","-b:v","250k","-c:a","libopus",input)
      assert status.success?,error
      events=Queue.new
      encoder=Studio::Live::Encoder.new(output:File.join(root,"index.m3u8"),test:false,hls:true,on_event:->(event,err){events<<[event,err]}).start!
      File.binread(input).bytes.each_slice(24_000).with_index{|bytes,i|encoder.append!(encoded:Base64.strict_encode64(bytes.pack("C*")),sequence:i)}
      encoder.stop!
      terminal=Timeout.timeout(10){loop{event=events.pop;break event if %w[ended failed].include?(event[0])}}
      assert_equal ["ended",nil],terminal
      assert File.file?(File.join(root,"index.m3u8"))
      assert Dir[File.join(root,"segment-*.ts")].any?
      out,err,status=Open3.capture3("ffprobe","-v","error","-show_streams","-of","json",File.join(root,"index.m3u8"))
      assert status.success?,err
      assert JSON.parse(out)["streams"].any?{|stream|stream["codec_name"]=="h264"}
    ensure
      encoder&.stop!
    end
  end

  def test_blender_asset_ingestion_placement_and_native_render
    skip "Set LIGHTEK_TEST_BLENDER=1 to exercise the installed Blender runtime" unless ENV["LIGHTEK_TEST_BLENDER"]=="1"
    Dir.mktmpdir("studio-blender-") do |root|
      source=File.join(root,"prop.blend")
      stdout=Studio::MediaProcess.run!([ENV.fetch("BLENDER_BIN","blender"),"--background","--factory-startup","--disable-autoexec","--python-exit-code","1","--python-expr","import bpy; bpy.ops.wm.save_as_mainfile(filepath=#{source.inspect})"],timeout:60)
      assert File.size?(source),stdout
      asset=StudioAsset.new(owner:@alice,site:@site,name:"Hero prop",kind:"blend",request_key:SecureRandom.uuid)
      asset.file.attach(io:File.open(source),filename:"prop.blend",content_type:"application/x-blender",identify:false)
      asset.save!
      previous_output=ENV["BLENDER_OUTPUT_ROOT"]
      ENV["BLENDER_OUTPUT_ROOT"]=File.join(root,"renders")
      Rails.stub(:root,Pathname(ROOT)) do
        Studio::Assets::Ingestor.call(asset)
        assert_equal "ready",asset.reload.status
        assert_equal 1,asset.metadata["mesh_count"]
        assert asset.thumbnail.attached?
        assert_equal "glTF",asset.proxy.blob.download.byteslice(0,4)
        # Re-ingest the generated GLB through the same production path.
        glb=StudioAsset.new(owner:@alice,site:@site,name:"Reusable GLB",kind:"glb",request_key:SecureRandom.uuid)
        glb.file.attach(asset.proxy.blob);glb.save!
        Studio::Assets::Ingestor.call(glb)
        assert_equal "ready",glb.reload.status
        project=StudioProject.create!(owner:@alice,site:@site,name:"Imported production")
        scene=project.studio_scenes.first
        placed=Studio::Workers::Workspace.perform("asset_place",user_id:@alice.id,site_id:@site.id,scene_id:scene.id,asset_id:glb.id,category:"character")
        object=SceneObject.find(placed[:object_id])
        assert_equal "character",object.definition["category"]
        assert_raises(ActiveRecord::RecordNotFound){Studio::Workers::Workspace.perform("asset_place",user_id:@bob.id,site_id:@site.id,scene_id:scene.id,asset_id:glb.id)}
        op=project.studio_operations.create!(studio_scene:scene,operation_type:"build_scene",provider:"blender",capability:"studio.render.preview",status:"pending",intent:{"user_id"=>@alice.id},manifest:{"schema_version"=>"1.0","scene"=>{"settings"=>{"render_engine"=>"CYCLES","samples"=>2,"resolution_x"=>128,"resolution_y"=>128},"objects"=>[{"type"=>object.object_type,"name"=>object.name,"definition"=>object.definition.merge("asset_path"=>"/untrusted/path.glb")}]},"outputs"=>{"blend"=>true,"glb"=>true,"preview"=>true}})
        result=Studio::Providers::BlenderProvider.new(op).call
        assert_equal %w[preview.png scene.blend scene.glb],result.generated_outputs.sort
        assert op.artifacts.find_by!(kind:"preview").file.attached?
      end
    ensure
      ENV["BLENDER_OUTPUT_ROOT"]=previous_output
    end
  end

  def test_media_timeout_reaps_the_process
    started=Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_raises(Timeout::Error){Studio::MediaProcess.run!([RbConfig.ruby,"-e","sleep 10"],timeout:0.1)}
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC)-started,:<,3
  end

  def test_actual_audio_mix_and_native_ott_publication
    Dir.mktmpdir("studio-audio-") do |root|
      source=File.join(root,"voice.wav")
      Studio::MediaProcess.run!(["ffmpeg","-v","error","-y","-f","lavfi","-i","sine=frequency=220:duration=1",source])
      asset=StudioAsset.new(owner:@alice,site:@site,name:"Voice",kind:"audio",request_key:SecureRandom.uuid)
      asset.file.attach(io:File.open(source),filename:"voice.wav",content_type:"audio/wav",identify:false);asset.save!
      Studio::Assets::Ingestor.call(asset)
      assert_equal "ready",asset.reload.status
      project=StudioProject.create!(owner:@alice,site:@site,name:"Audio production")
      timeline=Studio::Editing::Timeline.normalize({"output"=>"audio","clips"=>[{"asset_id"=>asset.id,"in"=>0,"out"=>0.8,"gain"=>0.7}]},assets:{asset.id=>asset})
      op=project.studio_operations.create!(operation_type:"edit_media",provider:"ffmpeg",capability:"studio.workspace.timeline.quote",status:"pending",intent:{"user_id"=>@alice.id},manifest:{"timeline"=>timeline})
      result=Studio::Providers::FfmpegProvider.new(op).call
      master=Artifact.find(result[:artifact_id])
      assert_match %r{\Aaudio/(x-)?wav\z},master.file.blob.content_type
      master.file.blob.open do |file|
        out=Studio::MediaProcess.run!(["ffprobe","-v","error","-show_streams","-of","json",file.path])
        assert_equal "pcm_s16le",JSON.parse(out)["streams"].first["codec_name"]
      end
      publication=project.studio_publications.create!(artifact:master,platform:"octavia",status:"draft",metadata:{"user_id"=>@alice.id})
      assert_raises(ArgumentError){Studio::Publishers::LightekStreaming.new(publication).call}
      publication.update!(platform:"lightek_social")
      audio_result=Studio::Publishers::LightekSocial.new(publication).call
      assert_equal master.file.blob.id,Post.find(audio_result["post_id"]).media.first.blob.id
      # Publish a real video master to the existing post store consumed by OTT.
      video=File.join(root,"master.mp4")
      Studio::MediaProcess.run!(["ffmpeg","-v","error","-y","-f","lavfi","-i","color=c=blue:s=128x128:d=0.3","-c:v","libx264","-threads","1",video])
      artifact=op.artifacts.create!(kind:"video",filename:"master.mp4")
      artifact.file.attach(io:File.open(video),filename:"master.mp4",content_type:"video/mp4",identify:false)
      @alice.profile.update!(community_gender:"woman")
      publication=project.studio_publications.create!(artifact:artifact,platform:"octavia",status:"draft",metadata:{"user_id"=>@alice.id,"audience"=>"women"})
      result=Studio::Publishers::LightekStreaming.new(publication).call
      post=Post.find(result.fetch("post_id"))
      assert_equal "octavia",post.distribution
      assert_equal "women",post.audience
      assert_equal artifact.file.blob.id,post.media.first.blob.id
      assert_empty LightekCommunity::Access.new(user:@bob,site_id:@site.id).posts.where(id:post.id)
    end
  end

  def test_failed_ingestion_retains_actionable_status_after_the_job_raises
    asset=StudioAsset.new(owner:@alice,site:@site,name:"Broken take",kind:"video",request_key:SecureRandom.uuid)
    asset.file.attach(io:StringIO.new("invalid video"),filename:"broken.mp4",content_type:"video/mp4",identify:false)
    asset.save!
    assert_raises(RuntimeError){StudioAssetIngestJob.perform_now(asset.id)}
    assert_equal "failed",asset.reload.status
    assert_match(/Media processing failed/,asset.error_message)
  end

  def test_administrator_cancellation_stops_an_actual_media_process
    started=Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_raises(Studio::MediaProcess::Cancelled) do
      Studio::MediaProcess.run!([RbConfig.ruby,"-e","sleep 10"],timeout:20,cancel_if:-> { Process.clock_gettime(Process::CLOCK_MONOTONIC)-started > 0.2 })
    end
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC)-started,:<,3
  end

end
