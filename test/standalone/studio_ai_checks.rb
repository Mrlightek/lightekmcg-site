# Local engine protocol tests use a loopback HTTP fixture and real asset ingest.
require_relative "studio_production_checks"
require "socket"
require File.join(ROOT,"app/services/studio/assets/ingestor")
require File.join(ROOT,"app/services/studio/ai/setup")
require File.join(ROOT,"app/services/studio/ai/runtime")
require File.join(ROOT,"app/services/studio/ai/input_image")
require File.join(ROOT,"app/services/studio/ai/generation")
require File.join(ROOT,"app/services/studio/ai/performances")
require File.join(ROOT,"app/jobs/studio_ai_generation_job")
class StudioAiTest < StudioProductionTest
  StudioProductionTest.instance_methods(false).grep(/^test_/).each{|method|undef_method(method)}
  def setup
    super
    FileUtils.mkdir_p(Rails.root.join("config/studio_ai/workflows"));FileUtils.cp(File.join(ROOT,"config/studio_ai/workflows/image.json"),Rails.root.join("config/studio_ai/workflows/image.json"))
    @old_url=ENV["STUDIO_AI_URL"];@server=TCPServer.new("127.0.0.1",0)
    ENV["STUDIO_AI_URL"]="http://127.0.0.1:#{@server.addr[1]}"
    @uploads=[];@extra_recipes=[];@supports_input=true;@upload_bad=false;@submitted=[];@completed=false;@engine_error=false;@models=["local.safetensors"]
    @image=IO.popen(["ffmpeg","-v","error","-f","lavfi","-i","color=c=blue:s=64x64","-frames:v","1","-threads","1","-f","image2pipe","-vcodec","png","-"],"rb",&:read)
    @thread=Thread.new do
      loop do
        socket=@server.accept
        first=socket.gets;headers={}
        while (line=socket.gets) && line!="\r\n"
          key,value=line.split(":",2);headers[key.downcase]=value.strip
        end
        body=socket.read(headers.fetch("content-length","0").to_i)
        method,path=first.split(" ");type="application/json"
        response=case path.split("?").first
        when "/object_info"
          recipe=JSON.parse(File.read(File.join(ROOT,"config/studio_ai/workflows/image.json")))
          nodes=recipe["workflow"].values.to_h{|n|[n["class_type"],{}]}
          @extra_recipes.each do |extra|
            extra["workflow"].each_value{|node|nodes[node["class_type"]] ||= {}}
            Array(extra["required_models"]).each{|spec|nodes[spec["node"]]={"input"=>{"required"=>{spec["field"]=>[[spec["name"]]]}}}}
          end
          nodes["Wan22ImageToVideoLatent"]={"input"=>{"optional"=>(@supports_input ? {"start_image"=>["IMAGE"]} : {})}} if nodes.key?("Wan22ImageToVideoLatent")
          nodes["CheckpointLoaderSimple"]={"input"=>{"required"=>{"ckpt_name"=>[@models]}}};nodes
        when "/system_stats"
          {"devices"=>[{"type"=>"cuda","vram_total"=>24.gigabytes,"vram_free"=>18.gigabytes,"name"=>"Registry device name"}]}
        when "/upload/image"
          @uploads<<body
          filename=body[/filename="([^"]+)"/,1]
          {"name"=>@upload_bad ? "../other.png" : filename,"subfolder"=>"lightek","type"=>"input"}
        when "/prompt"
          @submitted<<JSON.parse(body);{"prompt_id"=>"local-job-1"}
        when "/history/local-job-1"
          @completed ? {"local-job-1"=>{"status"=>{"completed"=>true,"status_str"=>@engine_error ? "error" : "success"},"outputs"=>{"9"=>{(@video ? "videos" : "images")=>[{"filename"=>(@video ? "result.mp4" : "result.png"),"subfolder"=>"","type"=>"output"}]}}}} : {}
        when "/view"
          type=@video ? "video/mp4" : "image/png";@video || @image
        else {}
        end
        bytes=type=="application/json" ? JSON.generate(response) : response
        socket.write("HTTP/1.1 200 OK\r\nContent-Type: #{type}\r\nContent-Length: #{bytes.bytesize}\r\nConnection: close\r\n\r\n");socket.write(bytes);socket.close
      end
    rescue IOError,Errno::EBADF
    end
  end
  def teardown
    @server&.close;@thread&.join(1);@thread&.kill
    ENV["STUDIO_AI_URL"]=@old_url
    super
  end
  def generate(**extra)
    action("ai_generate",scene_id:@scene.id,prompt:"An expressive original character in a recording studio",negative:"blur",recipe:"image",seed:42,model:"local.safetensors",request_key:"ai-generate-request-123",**extra)
  end
  def test_ai_bounded_steps_and_scoped_worker_telemetry
    status=action("ai_status",scene_id:@scene.id)
    assert_equal({type:"cuda",vram_total:24.gigabytes,vram_free:18.gigabytes},status[:device])
    assert_equal 20,status[:recipes].first[:steps]
    assert_equal %w[musetalk liveportrait facefusion],status[:performances].map { |item| item[:id] }
    assert_raises(ArgumentError){generate(steps:61)}
    assert_raises(ArgumentError){generate(steps:12.5)}
    output=generate(steps:"32")
    StudioAiGenerationJob.perform_now(output[:asset_id])
    assert_equal 32,@submitted.last.dig("prompt","3","inputs","steps")
  end

  def test_ai_performance_uses_scoped_pinned_media
    name = "STUDIO_MUSETALK_CPU_IMAGE"
    settings = [name, "STUDIO_CPU_DEDICATED_QUEUE", "STUDIO_CPU_SHARED_STORAGE", "STUDIO_CPU_WORKER"]
    before = settings.to_h { |key| [key, ENV[key]] }
    ENV[name] = "registry.example/musetalk@sha256:" + "a"*64
    ENV["STUDIO_CPU_DEDICATED_QUEUE"] = "1"
    ENV["STUDIO_CPU_SHARED_STORAGE"] = "1"
    ENV.delete("STUDIO_CPU_WORKER")
    source=StudioAsset.create!(owner:@alice,site_id:@site.id,kind:"image",status:"ready",name:"Portrait",request_key:"portrait-fixture")
    source.proxy.attach(io:StringIO.new(@image),filename:"portrait.png",content_type:"image/png")
    source.update!(metadata:{"width"=>64,"height"=>64})
    audio=recording
    audio.file.attach(io:StringIO.new("fixture"),filename:"fixture.wav",content_type:"audio/wav") unless audio.file.attached?
    audio.proxy.attach(audio.file.blob) unless audio.proxy.attached?
    audio.update!(metadata:audio.metadata.merge("duration"=>1.0))
    params={recipe:"musetalk",input_asset_id:source.id,driver_asset_id:audio.id,request_key:"performance-fixture",scene_id:@scene.id}
    result=action("ai_generate",**params)
    asset=StudioAsset.find(result[:asset_id])
    assert_equal [[asset.id, "studio_cpu"], [asset.id, "studio"]],
      ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job] == StudioAiGenerationJob && job[:args].first == asset.id }
        .map { |job| [job[:args].first, job[:queue]] }
    StudioAiGenerationJob.perform_now(asset.id)
    assert_equal "uploaded", asset.reload.status
    ENV["STUDIO_CPU_WORKER"] = "1"
    assert_equal source.proxy.blob.id,asset.ai_input.blob.id
    assert_equal audio.proxy.blob.id,asset.performance_driver.blob.id
    assert_equal result,action("ai_generate",**params)
    assert_raises(ArgumentError){action("ai_generate",**params.merge(request_key:"wrong-driver",driver_asset_id:source.id))}
    Dir.mktmpdir do |fixture|
      clip=File.join(fixture,"sample.mp4")
      Studio::MediaProcess.run!(["ffmpeg","-v","error","-f","lavfi","-i","color=c=blue:s=64x64:r=24",
        "-t","1","-c:v","libx264","-pix_fmt","yuv420p",clip])
      invoked=[]
      worker=lambda do |args,root:,image:,memory:,pull:|
        invoked << [args,image,memory,pull]
        assert File.file?(File.join(root,"source.png"))
        assert File.file?(File.join(root,"driver.wav"))
        ["cp",clip,File.join(root,"performance.mp4")]
      end
      FileUtils.mkdir_p(Rails.root.join("lib/scripts"))
      FileUtils.cp(File.join(ROOT,"lib/scripts/studio_performance_worker.py"),Rails.root.join("lib/scripts"))
      Studio::MediaProcess.stub(:container,worker) { StudioAiGenerationJob.perform_now(asset.id) }
      assert_equal ["python","/work/studio_performance_worker.py","musetalk","/work/source.png","/work/driver.wav"],invoked.first[0]
      assert_equal ENV[name],invoked.first[1]
      assert_equal "12g", invoked.first[2]
      assert_equal false, invoked.first[3]
      docker = Studio::MediaProcess.stub(:cpu_limit, "2") do
        Studio::MediaProcess.container(invoked.first[0], root: fixture, image: invoked.first[1], pull: invoked.first[3])
      end
      refute_includes docker, "--gpus"
      assert_equal "never", docker[docker.index("--pull") + 1]
      assert_equal "ready",asset.reload.status
      assert asset.proxy.attached?
      assert_equal "musetalk",action("ai_jobs",scene_id:@scene.id).first[:recipe]
    end
    queued = action("ai_generate", **params.merge(request_key: "performance-queue-timeout"))
    pending = StudioAsset.find(queued[:asset_id])
    pending.update!(created_at: 61.minutes.ago)
    StudioAiGenerationJob.perform_now(pending.id, true)
    assert_equal "failed", pending.reload.status
    assert_match(/did not pick up/, pending.error_message)

    interrupted = action("ai_generate", **params.merge(request_key: "performance-worker-timeout"))
    running = StudioAsset.find(interrupted[:asset_id])
    running.update!(status: "processing", metadata: running.metadata.merge(
      "ai_phase" => "performing", "ai_started_at" => 36.minutes.ago.iso8601))
    StudioAiGenerationJob.perform_now(running.id, true)
    assert_equal "failed", running.reload.status
    assert_match(/stopped before saving/, running.error_message)

    ENV["STUDIO_CPU_SHARED_STORAGE"] = "0"
    refute action("ai_status", scene_id: @scene.id)[:performances].first[:configured]
    assert_raises(ArgumentError) { action("ai_generate", **params.merge(request_key: "no-shared-storage")) }
    ENV["STUDIO_CPU_SHARED_STORAGE"] = "1"
    ENV[name]="mutable:latest"
    assert_raises(ArgumentError){action("ai_generate",**params.merge(request_key:"no-reviewed-image"))}
  ensure
    before&.each { |key, value| ENV[key] = value }
  end

  def test_ai_local_submission_poll_ingest_and_idempotency
    receipt=generate
    assert_equal receipt,generate
    asset=StudioAsset.find(receipt[:asset_id]);assert_equal @project.id,asset.studio_project_id
    StudioAiGenerationJob.perform_now(asset.id)
    assert_equal "processing",asset.reload.status
    assert_equal 1,@submitted.length
    assert_equal "local.safetensors",@submitted[0].dig("prompt","4","inputs","ckpt_name")
    assert_equal 42,@submitted[0].dig("prompt","3","inputs","seed")
    assert_equal "An expressive original character in a recording studio",@submitted[0].dig("prompt","6","inputs","text")
    refute asset.file.attached?
    @completed=true;StudioAiGenerationJob.perform_now(asset.id)
    assert_equal "ready",asset.reload.status
    assert asset.file.attached?;assert asset.proxy.attached?;assert asset.thumbnail.attached?
    assert_equal "ready",asset.metadata["ai_phase"]
    assert_equal 42,asset.metadata.dig("ai_intent","seed")
    refute asset.metadata.key?("ai_graph")
    StudioAiGenerationJob.perform_now(asset.id);assert_equal 1,@submitted.length
    assert_equal asset.id,action("ai_jobs",scene_id:@scene.id).first[:asset_id]
  end
  def test_ai_validates_scope_models_and_request_reuse
    assert_raises(ArgumentError){generate(model:"not-installed.safetensors")}
    assert_raises(ArgumentError){generate(seed:-1)}
    assert_raises(ActiveRecord::RecordNotFound){generate(user_id:@bob.id)}
    generate
    assert_raises(ArgumentError){generate(prompt:"Another shot")}
    foreign=StudioProject.create!(owner:@bob,site:@other_site,name:"Other")
    other=foreign.studio_scenes.create!(name:"Other")
    assert_raises(ActiveRecord::RecordNotFound){action("ai_jobs",scene_id:other.id)}
    @models=[];assert_empty action("ai_status",scene_id:@scene.id)[:recipes].select{|r|r[:ready]}
  end
  def test_ai_engine_failure_never_becomes_a_ready_asset
    receipt=generate;StudioAiGenerationJob.perform_now(receipt[:asset_id]);@completed=true;@engine_error=true
    StudioAiGenerationJob.perform_now(receipt[:asset_id]);asset=StudioAsset.find(receipt[:asset_id])
    assert_equal "failed",asset.status;refute asset.proxy.attached?
  end
  def test_ai_interrupted_submission_is_not_submitted_again
    asset=StudioAsset.find(generate[:asset_id])
    asset.update!(status:"processing",metadata:asset.metadata.merge("ai_phase"=>"submitting","ai_started_at"=>6.minutes.ago.iso8601))
    StudioAiGenerationJob.perform_now(asset.id)
    assert_equal "failed",asset.reload.status
    assert_empty @submitted
  end
  def test_ai_stale_preparation_recovers_without_regenerating
    asset=StudioAsset.find(generate[:asset_id]);StudioAiGenerationJob.perform_now(asset.id)
    asset.reload.update!(metadata:asset.metadata.merge("ai_phase"=>"preparing","ai_preparing_at"=>16.minutes.ago.iso8601,"ai_output"=>{"filename"=>"result.png","type"=>"output"}))
    StudioAiGenerationJob.perform_now(asset.id)
    assert_equal "ready",asset.reload.status
    assert_equal 1,@submitted.length
  end
  def test_ai_poll_connection_failure_keeps_the_confirmed_job
    asset=StudioAsset.find(generate[:asset_id]);StudioAiGenerationJob.perform_now(asset.id)
    @server.close;@thread.join(1)
    StudioAiGenerationJob.perform_now(asset.id)
    assert_equal "processing",asset.reload.status
    assert_equal "local-job-1",asset.metadata["ai_prompt_id"]
    assert_equal 1,@submitted.length
  end
  def test_ai_engine_is_local_and_outputs_cannot_traverse_paths
    runtime=Studio::Ai::Runtime.new
    assert_raises(ArgumentError){runtime.download({"filename"=>"../secret","subfolder"=>""})}
    assert_raises(ArgumentError){runtime.download({"filename"=>"image.png","subfolder"=>"../private"})}
    ENV["STUDIO_AI_URL"]="https://example.com"
    assert_raises(ArgumentError){Studio::Ai::Runtime.new}
  end
end
