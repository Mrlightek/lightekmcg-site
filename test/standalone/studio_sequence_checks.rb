require_relative "studio_character_scene_checks"
require File.join(ROOT,"app/services/lightek_pwa/media_ownership")
require File.join(ROOT,"app/services/studio/performance/sequence")
require File.join(ROOT,"app/jobs/studio_sequence_preview_job")
require File.join(ROOT,"app/services/studio/assets/ingestor")
require File.join(ROOT,"app/jobs/studio_asset_ingest_job")
require File.join(ROOT,"app/services/studio/providers/ffmpeg_provider")
require File.join(ROOT,"app/jobs/execute_studio_operation_job")
require File.join(ROOT,"app/services/studio/compute/queue")
require File.join(ROOT,"app/services/studio/compute/federation/dispatch")
# Model the bank's succeeded scope in the minimal standalone host.
class DymondBank::Transaction
  belongs_to :payable,polymorphic:true,optional:true
  scope :succeeded,-> { where(status:"succeeded") }
end
class StudioSequenceTest < StudioCharacterSceneTest
  StudioCharacterSceneTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def fixture_performance(name,color,tone,cast:nil)
    scene=@project.studio_scenes.create!(name:name,settings:StudioScene.default_settings.merge("fps"=>12,"frame_start"=>1,"frame_end"=>24,"resolution_x"=>640,"resolution_y"=>360))
    scene.scene_objects.create!(name:"Sentinel",object_type:"imported_asset",definition:{"asset_id"=>cast.id,"character_profile"=>cast.metadata["character_profile"]}) if cast
    manifest=Blender::ManifestBuilder.new(scene).call.deep_dup
    manifest["scene"]["settings"].merge!("resolution_x"=>320,"resolution_y"=>180,"samples"=>8)
    preview=scene.studio_operations.create!(studio_project:@project,capability:"studio.workspace.performance.preview",operation_type:"build_scene",provider:"blender",status:"completed",intent:{user_id:@alice.id},manifest:manifest,metadata:{draft_preview:true})
    Dir.mktmpdir do |root|
      file=File.join(root,"source.mp4")
      Studio::MediaProcess.run!(["ffmpeg","-v","error","-y","-f","lavfi","-i","color=c=#{color}:s=320x180:r=24:d=2","-f","lavfi","-i","sine=frequency=#{tone}:duration=2","-c:v","libx264","-threads","1","-pix_fmt","yuv420p","-c:a","aac","-shortest",file])
      artifact=preview.artifacts.create!(kind:"video",filename:"source.mp4");artifact.file.attach(io:File.open(file),filename:"source.mp4",content_type:"video/mp4",identify:false)
    end
    scene.studio_operations.create!(studio_project:@project,capability:Studio::Performance::CharacterScene::CAPABILITY,operation_type:"character_scene",provider:"studio",status:"completed",intent:{user_id:@alice.id},manifest:{inputs:{name:name}},metadata:{scene_id:scene.id,preview_id:preview.id})
  end
  def fixtures
    @sources||=[fixture_performance("Opening","red",220),fixture_performance("Reply","blue",440)]
  end
  def cut(**extra)
    action("sequence_prepare",scene_id:@scene.id,name:"Opening exchange",request_key:"sequence-cut-request-123",shots:fixtures.map { |parent| {operation_id:parent.id,in:0.25,out:1.75} },**extra)
  end
  def test_cut_scope_bounds_idempotence_and_canonical_source_fingerprints
    result=cut;assert_equal result,cut
    assert_equal 3,result[:seconds]
    assert_equal result,action("sequence_status",scene_id:@scene.id)
    assert_raises(ActiveRecord::RecordNotFound) { action("sequence_status",operation_id:result[:operation_id],user_id:@bob.id) }
    assert_raises(ArgumentError) { cut(name:"Another name") }
    assert_raises(ArgumentError) { cut(shots:[]) }
    assert_raises(ArgumentError) { cut(shots:[{operation_id:fixtures[0].id,in:-1,out:1},{operation_id:fixtures[1].id}]) }
    assert_raises(ArgumentError) { cut(shots:[{operation_id:fixtures[0].id,out:3},{operation_id:fixtures[1].id}]) }
    assert_raises(ArgumentError) { action("sequence_quote",operation_id:result[:operation_id],reviewed:true) }
    access=Studio::PwaAccess.new("user_id"=>@alice.id,"site_id"=>@site.id)
    data=Blender::ManifestBuilder.new(StudioScene.find(fixtures[0].metadata["scene_id"])).call["scene"]
    assert_equal Studio::Performance::Sequence.signature(data),Studio::Performance::Sequence.signature(data.to_a.reverse.to_h)
    assert action("sequence_catalog",scene_id:@scene.id)[:performances].all? { |row| row[:available] }
    target=StudioScene.find(fixtures[0].metadata["scene_id"]);target.update!(settings:target.settings.merge("world_color"=>[1,0,0,1]))
    assert_raises(ArgumentError) { action("sequence_retry",operation_id:result[:operation_id]) }
    refute action("sequence_catalog",scene_id:@scene.id)[:performances].find { |row| row[:operation_id]==fixtures[0].id }[:available]
  end
  def test_named_character_continuity_and_interrupted_worker_recovery
    cast_a=ready_actor;cast_b=ready_actor
    first=fixture_performance("Shot A","red",220,cast:cast_a)
    second=fixture_performance("Shot B","blue",440,cast:cast_b)
    error=assert_raises(ArgumentError) { cut(shots:[{operation_id:first.id},{operation_id:second.id}]) }
    assert_match(/Cast identities/,error.message)
    parent=StudioOperation.find(cut[:operation_id]);parent.update!(metadata:parent.metadata.merge("deadline"=>1.minute.ago.iso8601))
    StudioSequencePreviewJob.perform_now(parent.id)
    assert_equal "failed",parent.reload.status
    assert_empty parent.artifacts
    action("sequence_retry",operation_id:parent.id)
    assert_equal "pending",parent.reload.status
  end
  def test_full_source_handoff_creates_an_editable_timeline_and_reuses_the_export_quote
    Rails.stub(:root,Pathname(ROOT)) do
      parent=StudioOperation.find(cut[:operation_id]);StudioSequencePreviewJob.perform_now(parent.id)
      fixtures.each do |source|
        scene=StudioScene.find(source.metadata["scene_id"])
        manifest=Blender::ManifestBuilder.new(scene).call.merge("outputs"=>{"animation"=>true})
        full=scene.studio_operations.create!(studio_project:@project,capability:"studio.render.preview",operation_type:"build_scene",provider:"blender",status:"completed",intent:{user_id:@alice.id},manifest:manifest)
        preview=StudioOperation.find(source.metadata["preview_id"]).artifacts.find_by!(kind:"video")
        artifact=full.artifacts.create!(kind:"video",filename:"full.mp4");artifact.file.attach(preview.file.blob)
      end
      processing=action("sequence_quote",operation_id:parent.id,reviewed:true)
      assert_equal "processing_sources",processing[:status]
      processing[:asset_ids].each { |id| StudioAssetIngestJob.perform_now(id) }
      price=Studio::Billing::Quote.stub(:call,->(operation:,**_) { operation.update!(status:"awaiting_payment",cost_quote:{"total_cents"=>250,"currency"=>"USD"}) }) { action("sequence_quote",operation_id:parent.id,reviewed:true) }
      assert_equal "awaiting_payment",price[:status]
      assert_equal price[:operation_id],action("sequence_quote",operation_id:parent.id,reviewed:true)[:operation_id]
      edit=StudioScene.find(price[:edit_scene_id]);refute_equal @scene.id,edit.id
      timeline=edit.settings.fetch("timeline");assert_equal [0,1.5],timeline["clips"].map { |clip| clip["start"] }
      assert_equal [0.25,0.25],timeline["clips"].map { |clip| clip["in"] }
      export=StudioOperation.find(price[:operation_id]);assert_equal 2,export.performance_sources.count
      imported=StudioAsset.find(processing[:asset_ids].first)
      imported.file.attach(io:StringIO.new("changed source"),filename:"changed.mp4",content_type:"video/mp4",identify:false)
      assert_equal export.id,action("sequence_quote",operation_id:parent.id,reviewed:true)[:operation_id]
      Studio::Providers::FfmpegProvider.new(export).call
      export.artifacts.find_by!(kind:"video").file.blob.open do |file|
        info=JSON.parse(IO.popen(["ffprobe","-v","error","-show_streams","-show_format","-of","json",file.path],&:read))
        assert_in_delta 3,info["format"]["duration"].to_f,0.1
        assert_equal 1280,info["streams"].find { |stream| stream["codec_type"]=="video" }["width"]
      end
      export.update!(status:"failed",error_message:"worker interruption")
      assert_equal "failed",action("sequence_quote",operation_id:parent.id,reviewed:true)[:status]
      DymondBank::Transaction.create!(payable:export,status:"succeeded",amount_cents:250)
      original=StudioScene.find(fixtures[0].metadata["scene_id"]);original.update!(settings:original.settings.merge("world_color"=>[0.9,0,0,1]))
      assert_equal "pending",action("sequence_quote",operation_id:parent.id,reviewed:true)[:status]
      assert_equal export.id,action("sequence_quote",operation_id:parent.id,reviewed:true)[:operation_id]
      assert_equal 1,DymondBank::Transaction.where(payable:export).count
      edit.update!(settings:edit.settings.merge("timeline"=>timeline.merge("width"=>640)))
      assert_raises(ArgumentError) { action("sequence_quote",operation_id:parent.id,reviewed:true) }
    end
  end
  def test_sequence_from_existing_animation_proofs
    skip "Set STUDIO_SEQUENCE_PROOF_SOURCES to reuse the native animation proof files" unless ENV["STUDIO_SEQUENCE_PROOF_SOURCES"]
    files=JSON.parse(ENV.fetch("STUDIO_SEQUENCE_PROOF_SOURCES"));assert_equal 2,files.size
    Rails.stub(:root,Pathname(ROOT)) do
      expected=0
      fixtures.zip(files).each do |source,file|
        info=JSON.parse(IO.popen(["ffprobe","-v","error","-show_entries","format=duration","-of","json",file],&:read))
        expected+=info["format"]["duration"].to_f
        scene=StudioScene.find(source.metadata["scene_id"])
        scene.update!(settings:scene.settings.merge("frame_end"=>(info["format"]["duration"].to_f*12).round))
        preview=StudioOperation.find(source.metadata["preview_id"]);data=Blender::ManifestBuilder.new(scene).call
        data["scene"]["settings"].merge!("resolution_x"=>320,"resolution_y"=>180,"samples"=>8);preview.update!(manifest:data)
        preview.artifacts.find_by!(kind:"video").file.attach(io:File.open(file),filename:"animation.mp4",content_type:"video/mp4",identify:false)
      end
      value=action("sequence_prepare",scene_id:@scene.id,name:"Animated sequence review",request_key:"animated-sequence-proof-123",shots:fixtures.map { |parent| {operation_id:parent.id} })
      StudioSequencePreviewJob.perform_now(value[:operation_id]);parent=StudioOperation.find(value[:operation_id]);assert_equal "completed",parent.status
      parent.artifacts.find_by!(kind:"video").file.blob.open { |file| FileUtils.cp(file.path,ENV.fetch("STUDIO_SEQUENCE_PROOF_VIDEO")) }
      assert_in_delta expected,action("sequence_status",operation_id:parent.id)[:seconds],0.1
    end
  end
  def test_real_private_cut_preserves_order_trims_audio_and_requires_full_sources_for_delivery
    Rails.stub(:root,Pathname(ROOT)) do
      parent=StudioOperation.find(cut[:operation_id]);StudioSequencePreviewJob.perform_now(parent.id)
      assert_equal "completed",parent.reload.status,parent.error_message
      assert_equal 2,parent.performance_sources.count
      artifact=parent.artifacts.find_by!(kind:"video")
      assert_raises(ArgumentError) { action("artifact_reuse",project_id:@project.id,artifact_id:artifact.id) }
      assert_raises(ArgumentError) { action("sequence_quote",operation_id:parent.id) }
      delivery=action("sequence_quote",operation_id:parent.id,reviewed:true)
      assert_equal "source_exports_required",delivery[:status];assert_equal 2,delivery[:missing].size
      artifact.file.blob.open do |file|
        info=JSON.parse(IO.popen(["ffprobe","-v","error","-show_streams","-show_format","-of","json",file.path],&:read))
        assert_in_delta 3,info["format"]["duration"].to_f,0.1
        assert_equal 320,info["streams"].find { |stream| stream["codec_type"]=="video" }["width"]
        [0.5,2.0].each_with_index do |time,index|
          rgb=IO.popen(["ffmpeg","-v","error","-ss",time.to_s,"-i",file.path,"-frames:v","1","-vf","scale=1:1","-pix_fmt","rgb24","-f","rawvideo","-"],"rb",&:read).bytes
          assert_operator rgb[index==0 ? 0 : 2],:>,200
          samples=IO.popen(["ffmpeg","-v","error","-ss",time.to_s,"-t","0.25","-i",file.path,"-vn","-ac","1","-ar","8000","-f","s16le","-"],"rb",&:read).unpack("s<*")
          crossings=samples.each_cons(2).count { |a,b| a<=0 && b>0 }
          assert_in_delta index==0 ? 220 : 440,crossings/0.25,12,"The selected clip's voice must follow the same cut order"
        end
      end
      parent.update!(status:"failed");action("sequence_retry",operation_id:parent.id);StudioSequencePreviewJob.perform_now(parent.id)
      assert_equal "completed",parent.reload.status
      assert_equal 2,parent.artifacts.count # retained attempt evidence, one new completed result
      assert_empty @scene.scene_objects
    end
  end
end
