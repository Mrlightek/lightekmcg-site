require_relative "studio_library_checks"
%w[app/services/studio/providers/blender_provider app/services/studio/providers/registry app/services/studio/operations/dispatcher app/jobs/execute_studio_operation_job app/services/studio/workers/preview].each { |file| require File.join(ROOT,file) }
# The standalone host replaces the bank query adapter, not the paid-render check.
class DymondBank::Transaction
  belongs_to :payable,polymorphic:true,optional:true
  scope :succeeded,-> { where(status:"succeeded") }
end
class StudioCpuEconomyTest < StudioLibraryTest
  StudioLibraryTest.instance_methods(false).grep(/^test_/).each { |m| undef_method(m) }
  def operation(status:"failed",paid:true)
    @scene.update!(settings:@scene.settings.merge("compute_profile"=>"cpu_economy","render_engine"=>"CYCLES","resolution_x"=>64,"resolution_y"=>64,"samples"=>1,"fps"=>12,"frame_start"=>1,"frame_end"=>3))
    manifest=Blender::ManifestBuilder.new(@scene).call;manifest["outputs"]={"animation"=>true,"blend"=>true}
    op=@scene.studio_operations.create!(studio_project:@project,operation_type:"build_scene",provider:"blender",capability:"studio.render.preview",status:status,intent:{user_id:@alice.id},manifest:manifest)
    DymondBank::Transaction.create!(payable:op,status:"succeeded",amount_cents:500) if paid
    op
  end
  def test_cpu_profile_caps_resolved_work_preserves_source_and_rejects_invalid_profile
    @scene.update!(settings:@scene.settings.merge("compute_profile"=>"cpu_economy","resolution_x"=>1920,"resolution_y"=>1080,"samples"=>128))
    resolved=Blender::ManifestBuilder.new(@scene).call.dig("scene","settings")
    assert_equal [512,288,8,"CYCLES"],resolved.values_at("resolution_x","resolution_y","samples","render_engine")
    assert_equal 1920,@scene.reload.settings["resolution_x"]
    assert_raises(ArgumentError) { Studio::Compute::CpuProfile.settings(@scene.settings.merge("compute_profile"=>"cuda_fake")) }
    assert_raises(ArgumentError) { action("visual_save",scene_id:@scene.id,lock_version:@scene.lock_version,render_settings:{render_engine:"CYCLES",compute_profile:"execute",resolution_x:64,resolution_y:64}) }
    result=action("visual_save",scene_id:@scene.id,lock_version:@scene.reload.lock_version,render_settings:{render_engine:"CYCLES",compute_profile:"cpu_economy",resolution_x:1280,resolution_y:720,samples:32})
    assert_equal @scene.reload.lock_version,result[:lock_version];assert_equal "cpu_economy",@scene.settings["compute_profile"]
  end
  def test_resume_requires_authorized_paid_failed_snapshot_and_only_enqueues_once
    op=operation;before=ActiveJob::Base.queue_adapter.enqueued_jobs.count { |job| job[:job]==ExecuteStudioOperationJob }
    first=action("render_resume",operation_id:op.id);assert_equal first,action("render_resume",operation_id:op.id)
    assert_equal before+1,ActiveJob::Base.queue_adapter.enqueued_jobs.count { |job| job[:job]==ExecuteStudioOperationJob }
    assert_equal "pending",op.reload.status;assert_equal 1,DymondBank::Transaction.where(payable:op).count
    unpaid=operation(paid:false);assert_raises(ArgumentError) { action("render_resume",operation_id:unpaid.id) }
    cancelled=operation(status:"cancelled");assert_raises(ArgumentError) { action("render_resume",operation_id:cancelled.id) }
    @project.update!(owner:@bob,site:@other_site)
    assert_raises(ActiveRecord::RecordNotFound) { action("render_resume",operation_id:op.id) }
  end
  def test_cpu_slot_defers_a_real_job_without_marking_it_failed
    op=operation(status:"pending");dispatcher=Object.new
    dispatcher.define_singleton_method(:call) { Studio::Compute::CpuProfile.with_slot { true } }
    Studio::Compute::CpuProfile.with_slot do
      assert_raises(Studio::Compute::CpuProfile::Busy) { Studio::Compute::CpuProfile.with_slot { flunk } }
      Studio::Operations::Dispatcher.stub(:new,->(_operation) { dispatcher }) { ExecuteStudioOperationJob.perform_now(op.id) }
    end
    assert_equal "pending",op.reload.status;assert_equal "waiting_for_cpu_slot",op.metadata.dig("cpu_render_progress","phase")
    assert ActiveJob::Base.queue_adapter.enqueued_jobs.any? { |job| job[:job]==ExecuteStudioOperationJob && job[:args]==[op.id] }
    Studio::Operations::Dispatcher.stub(:new,->(_operation) { dispatcher }) { ExecuteStudioOperationJob.perform_now(op.id) }
    assert_equal "completed",op.reload.status
  end
  def test_nevaeh_preview_reports_a_deferred_cpu_job_without_a_fake_artifact
    op=operation(status:"pending");dispatcher=Object.new
    dispatcher.define_singleton_method(:call) { Studio::Compute::CpuProfile.with_slot { true } }
    Studio::Compute::CpuProfile.with_slot do
      Studio::Operations::Dispatcher.stub(:new,->(_operation) { dispatcher }) do
        receipt=Studio::Workers::Preview.perform(op.id,"cpu-slot-test")
        assert_equal "pending",receipt["status"];assert_equal "waiting_for_cpu_slot",receipt["phase"];refute receipt.key?("artifact_id")
      end
    end
  end
  def test_cpu_container_budget_has_no_gpu_and_preserves_existing_quoted_checkout
    op=operation
    Rails.stub(:env,ActiveSupport::StringInquirer.new("production")) do
      command=Blender::Runner.new(op).send(:command)
      assert_equal "1g",command[command.index("--memory")+1]
      assert_equal "1",command[command.index("--cpus")+1]
      refute_includes command,"--gpus"
    end
    assert op.paid?
  end
  def test_real_cpu_native_soundtrack_survives_frame_encoding
    skip "Set LIGHTEK_TEST_BLENDER=1" unless ENV["LIGHTEK_TEST_BLENDER"]=="1"
    op=operation(status:"running")
    Dir.mktmpdir("cpu-audio-") do |root|
      wave=File.join(root,"voice.wav");source=File.join(root,"source.blend")
      Studio::MediaProcess.run!(["ffmpeg","-v","error","-y","-f","lavfi","-i","sine=frequency=440:sample_rate=48000","-t","0.25",wave])
      code="import bpy; bpy.ops.wm.read_factory_settings(use_empty=False); s=bpy.context.scene; s.name='CPU audio'; e=s.sequence_editor_create(); strips=e.strips if hasattr(e,'strips') else e.sequences; strips.new_sound('Score',#{wave.inspect},channel=1,frame_start=1); bpy.ops.file.pack_all(); bpy.ops.wm.save_as_mainfile(filepath=#{source.inspect})"
      Studio::MediaProcess.run!(["blender","--background","--factory-startup","--disable-autoexec","--python-exit-code","1","--python-expr",code],timeout:60)
      manifest=op.manifest.deep_dup;manifest["scene"]["settings"]["native_scene"]="CPU audio";op.update!(manifest:manifest)
      previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=root
      result=Rails.stub(:root,Pathname(ROOT)) { Blender::Runner.new(op,template_path:source).call }
      streams=JSON.parse(Studio::MediaProcess.run!(["ffprobe","-v","error","-show_entries","stream=codec_type","-of","json",result.output_directory.join("movie.mp4").to_s]))["streams"]
      assert streams.any? { |stream| stream["codec_type"]=="audio" }
      pixels=Studio::MediaProcess.run!(["ffmpeg","-v","error","-i",result.output_directory.join("cpu-frames/frame-000001.png").to_s,"-frames:v","1","-f","rawvideo","-pix_fmt","rgb24","-"])
      assert pixels.bytes.sum>1000,"A sound-only sequencer must not replace the camera picture with black"
      assert_equal "completed",op.reload.metadata.dig("cpu_render_progress","phase")
    ensure
      ENV["BLENDER_OUTPUT_ROOT"]=previous
    end
  end
  def test_real_stateful_simulation_rejects_checkpoint_profile
    skip "Set LIGHTEK_TEST_BLENDER=1" unless ENV["LIGHTEK_TEST_BLENDER"]=="1"
    Dir.mktmpdir("cpu-stateful-") do |root|
      script=File.join(root,"guard.py")
      File.write(script,"import bpy, sys\nsys.path.insert(0,#{File.join(ROOT,'blender').inspect})\nimport cpu_render\nbpy.context.object.modifiers.new('Cloth','CLOTH')\ntry:\n cpu_render.configure({'compute_profile':'cpu_economy','resolution_x':64,'resolution_y':64})\nexcept ValueError as error:\n assert 'stateful' in str(error); print('CPU_STATEFUL_GUARD_PASS')\nelse:\n raise AssertionError('Checkpoint rendering cannot pretend simulation state was restored')\n")
      result=Studio::MediaProcess.run!(["blender","--background","--factory-startup","--disable-autoexec","--python-exit-code","1","--python",script],timeout:30)
      assert_includes result,"CPU_STATEFUL_GUARD_PASS"
    end
  end
  def test_real_cpu_economy_benchmark_at_profile_limits
    skip "Set LIGHTEK_TEST_BLENDER=1" unless ENV["LIGHTEK_TEST_BLENDER"]=="1"
    op=operation(status:"running");@scene.scene_objects.create!(name:"CPU benchmark cube",object_type:"cube",definition:{location:[0,0,0],rotation:[0,0,0],scale:[1,1,1]})
    @scene.update!(settings:@scene.settings.merge("resolution_x"=>1280,"resolution_y"=>720,"samples"=>32,"fps"=>24,"frame_end"=>12))
    manifest=Blender::ManifestBuilder.new(@scene).call;manifest["outputs"]={"animation"=>true};op.update!(manifest:manifest)
    Dir.mktmpdir("cpu-benchmark-") do |root|
      previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=root
      result=Rails.stub(:root,Pathname(ROOT)) { Studio::Providers::BlenderProvider.new(op).call }
      metrics=op.reload.metadata["cpu_render_progress"];assert_equal 12,metrics["completed_frames"];assert_equal "completed",metrics["phase"]
      puts "CPU_ECONOMY_BENCHMARK=#{metrics.to_json}"
      assert_equal [512,288,8],manifest.dig("scene","settings").values_at("resolution_x","resolution_y","samples")
    ensure
      ENV["BLENDER_OUTPUT_ROOT"]=previous
    end
  end
  def test_real_cpu_movie_repairs_corrupt_frame_reuses_checkpoints_and_keeps_artifact_identity
    skip "Set LIGHTEK_TEST_BLENDER=1" unless ENV["LIGHTEK_TEST_BLENDER"]=="1"
    @scene.scene_objects.create!(name:"Procedural cube",object_type:"cube",definition:{location:[0,0,0],rotation:[0,0,0],scale:[1,1,1]})
    op=operation(status:"running")
    Dir.mktmpdir("cpu-economy-") do |root|
      previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=root
      execute=-> { Rails.stub(:root,Pathname(ROOT)) { Studio::Providers::BlenderProvider.new(op).call } }
      result=execute.call;progress=op.reload.metadata.fetch("cpu_render_progress")
      assert_equal 3,progress["completed_frames"];assert_equal 0,progress["reused_frames"];assert progress["blender_peak_rss_bytes"]>0
      directory=result.output_directory;frame=directory.join("cpu-frames/frame-000002.png");frame.binwrite("interrupted file")
      ids=op.artifacts.order(:id).pluck(:id);execute.call
      assert_equal 2,op.reload.metadata.dig("cpu_render_progress","reused_frames")
      assert_equal "\x89PNG".b,frame.binread(4)
      execute.call;assert_equal 3,op.reload.metadata.dig("cpu_render_progress","reused_frames")
      assert_equal ids,op.artifacts.order(:id).pluck(:id),"resuming cannot duplicate output artifact records"
      changed=op.manifest.deep_dup;changed["scene"]["objects"][0]["definition"]["location"]=[0.5,0,0];op.update!(manifest:changed);execute.call
      assert_equal 0,op.reload.metadata.dig("cpu_render_progress","reused_frames"),"a changed source fingerprint cannot reuse old picture"
      probe=JSON.parse(Studio::MediaProcess.run!(["ffprobe","-v","error","-select_streams","v:0","-show_entries","stream=width,height,nb_frames","-of","json",directory.join("movie.mp4").to_s]))["streams"].first
      assert_equal [64,64,"3"],probe.values_at("width","height","nb_frames")
      assert_equal 0700,File.stat(directory).mode & 0777
      Rails.stub(:root,Pathname(ROOT)) { Blender::Runner.new(op).clear_checkpoints! }
      refute directory.join("cpu-frames").exist?;assert directory.join("movie.mp4").exist?
    ensure
      ENV["BLENDER_OUTPUT_ROOT"]=previous
    end
  end
end
