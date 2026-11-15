require_relative "studio_ai_checks"
class StudioAiImageVideoTest < StudioAiTest
  StudioAiTest.instance_methods(false).grep(/^test_/).each{|method|undef_method(method)}
  def setup
    super
    recipe=JSON.parse(File.read(File.join(ROOT,"config/studio_ai/workflows/wan22_image_video.json")))
    File.write(Rails.root.join("config/studio_ai/workflows/wan22_image_video.json"),JSON.generate(recipe));@extra_recipes=[recipe]
  end
  def image_source(owner:@alice,site:@site)
    source=StudioAsset.new(owner:owner,site:site,kind:"image",status:"ready",name:"Starting still",request_key:SecureRandom.uuid,metadata:{width:64,height:64})
    source.file.attach(io:StringIO.new(@image),filename:"starting.png",content_type:"image/png",identify:false)
    source.proxy.attach(source.file.blob);source.save!;source
  end
  def image_video(**extra)
    @source ||= image_source
    generate(recipe:"wan22_image_video",model:"",input_asset_id:@source.id,**extra)
  end
  def test_image_video_freezes_input_uploads_png_submits_conditioning_and_ingests_real_video
    receipt=image_video;assert_equal receipt,image_video
    assert_includes action("assets_list",surface:"ai_input",scope_site:true)[:assets].map{|item|item[:id]},@source.id
    asset=StudioAsset.find(receipt[:asset_id]);assert_equal @source.id,receipt[:input_asset_id]
    assert asset.ai_input.attached?;assert_equal @image,asset.ai_input.download
    # The standalone host has no mounted Active Storage route helpers.
    routes=Rails.application.routes.url_helpers
    routes.define_singleton_method(:rails_blob_path){|attachment,**|"/fixture-blobs/#{attachment.blob.id}"}
    begin
      client=session_for;client.get receipt[:input_url],headers:headers
      assert_equal 302,client.response.status,client.response.body.first(1500)
      assert client.response.location.end_with?("/fixture-blobs/#{asset.ai_input.blob.id}")
      client.get receipt[:input_url].sub("site_id=#{@site.id}","site_id=#{@other_site.id}"),headers:headers
      assert_equal 404,client.response.status
    ensure
      routes.singleton_class.remove_method(:rails_blob_path)
    end
    @source.proxy.attach(io:StringIO.new("changed"),filename:"different.png",content_type:"image/png",identify:false)
    assert_equal @image,asset.reload.ai_input.download
    bytes=Studio::Ai::InputImage.prepare(asset);assert bytes.start_with?("\x89PNG\r\n\x1a\n".b)
    assert_equal [1280,704],bytes.byteslice(16,8).unpack("NN")
    Dir.mktmpdir do |root|
      path=File.join(root,"result.mp4");Studio::MediaProcess.run!(["ffmpeg","-v","error","-y","-f","lavfi","-i","color=c=blue:s=128x72:r=24","-t","0.5","-c:v","libx264","-threads","1",path]);@video=File.binread(path)
    end
    StudioAiGenerationJob.perform_now(asset.id)
    assert_equal 1,@uploads.length;assert_includes @uploads[0].b,"\x89PNG\r\n\x1a\n".b
    assert_equal 1,@submitted.length
    graph=@submitted[0]["prompt"]
    assert_equal ["60",0],graph.dig("55","inputs","start_image")
    assert_match %r{\Alightek/lightek-#{asset.id}-[a-f0-9]+\.png\z},graph.dig("60","inputs","image")
    assert_equal 42,graph.dig("3","inputs","seed")
    @completed=true;StudioAiGenerationJob.perform_now(asset.id)
    assert_equal "ready",asset.reload.status;assert_equal "video",asset.kind;assert asset.proxy.attached?
    assert asset.ai_input.attached?;assert_equal @image,asset.ai_input.download
    StudioAiGenerationJob.perform_now(asset.id);assert_equal 1,@submitted.length
  end
  def test_image_video_rejects_foreign_missing_unready_and_unsupported_sources
    foreign=image_source(owner:@bob,site:@other_site)
    assert_raises(ActiveRecord::RecordNotFound){image_video(input_asset_id:foreign.id)}
    assert_raises(ArgumentError){image_video(input_asset_id:nil)}
    assert_raises(ArgumentError){image_video(input_asset_id:"../source.png")}
    @source.update!(status:"processing");assert_raises(ArgumentError){image_video}
    @source.update!(status:"ready",kind:"video");assert_raises(ArgumentError){image_video}
    @source.update!(kind:"image",metadata:{width:10000,height:10000});assert_raises(ArgumentError){image_video}
    @source.update!(metadata:{width:64,height:64})
    assert_raises(ArgumentError){generate(input_asset_id:@source.id)}
    assert_empty @uploads;assert_empty @submitted
  end
  def test_image_video_inventory_checks_conditioning_input_and_idempotency_keeps_snapshot
    @supports_input=false
    assert_raises(ArgumentError){image_video}
    @supports_input=true;receipt=image_video
    @source.update!(status:"failed");assert_equal receipt,image_video
    assert_raises(ArgumentError){image_video(input_asset_id:image_source.id)}
    assert_empty @uploads
  end
  def test_image_video_rejects_unconfirmed_upload_without_prompt_or_automatic_resubmission
    asset=StudioAsset.find(image_video[:asset_id]);@upload_bad=true
    StudioAiGenerationJob.perform_now(asset.id)
    assert_equal "failed",asset.reload.status;assert_empty @submitted;assert_equal 1,@uploads.length
    StudioAiGenerationJob.perform_now(asset.id);assert_equal 1,@uploads.length
  end
end
