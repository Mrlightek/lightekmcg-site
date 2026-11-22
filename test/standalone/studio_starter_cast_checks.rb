# frozen_string_literal: true
require_relative "studio_production_checks"
require File.join(ROOT,"app/services/studio/native_blender/starter_cast")
require File.join(ROOT,"app/jobs/studio_starter_cast_job")
Minitest.after_run { FileUtils.remove_entry(Rails.application.config.root.to_s) if File.basename(Rails.application.config.root.to_s).start_with?("lightek-community-tests") }
class StudioStarterCastTest < StudioProductionTest
  StudioProductionTest.instance_methods(false).grep(/^test_/).each{|method|undef_method(method)}
  def start_cast(**extra)
    action("starter_scene_create",name:"Our first short",request_key:"starter-cast-test-request",**extra)
  end
  def test_starter_cast_is_idempotent_scoped_and_reports_its_job
    first=start_cast;assert_equal first,start_cast
    assert_equal "queued",first[:phase]
    assert_equal first,action("starter_scene_status",asset_id:first[:asset_id])
    assert_equal first,action("starter_scene_status")
    assert_raises(ActiveRecord::RecordNotFound){action("starter_scene_status",asset_id:first[:asset_id],site_id:@other_site.id)}
    assert_raises(ArgumentError){start_cast(name:"Different request")}
  end
  def test_starter_cast_saves_character_options_and_rejects_reusing_a_key_for_other_edits
    character={rig:"snow_v4",height:1.15,facing:-30,tint:"#B08050"}
    result=start_cast(character:character)
    assert result[:variant]
    assert_equal ["snow_v4",1.15,-30,"#b08050"],
      StudioAsset.find(result[:asset_id]).metadata.dig("starter_cast","character").values_at("rig","height","facing","tint")
    assert_equal result,start_cast(character:character)
    assert_raises(ArgumentError) { start_cast(character:character.merge(height:0.49)) }
    assert_raises(ArgumentError) { start_cast(character:character.merge(rig:"rain_v3")) }
  end

  def test_starter_cast_validates_ellie_poses
    result=start_cast(character:{rig:"ellie_v2",pose:"waving"})
    asset=StudioAsset.find(result[:asset_id])
    assert_equal "waving",asset.metadata.dig("starter_cast","character","pose")
    assert_equal "CC-BY 4.0",asset.metadata.dig("source","credits",0,"license")
    refute result[:base_mesh]
    assert_raises(ArgumentError){start_cast(character:{rig:"ellie_v2",pose:"unknown"})}
    assert_raises(ArgumentError){start_cast(character:{rig:"human_female_stylized",pose:"waving"})}
  end

  def test_starter_cast_builds_projects_from_official_character_bundles
    ellie=ENV["STUDIO_ELLIE_ARCHIVE"]
    human=ENV["STUDIO_HUMAN_MESH_ARCHIVE"]
    skip "Set the paths to the verified Ellie and human mesh archives" unless ellie && human

    [
      [{rig:"ellie_v2",pose:"waving"},ellie,false],
      [{rig:"human_female_stylized"},human,true]
    ].each do |character,path,is_mesh|
      key=SecureRandom.uuid
      started=start_cast(character:character,request_key:key)
      assert_equal is_mesh,started[:base_mesh]
      download=->(_url,target,**_args){FileUtils.cp(path,target)}
      Rails.stub(:root,Pathname(ROOT)) do
        Studio::NativeBlender::DemoImport.stub(:download,download){StudioStarterCastJob.perform_now(started[:asset_id])}
      end
      result=action("starter_scene_status",asset_id:started[:asset_id])
      assert_equal "ready",result[:phase],result[:error]
      scene=StudioScene.find(result[:scene_id])
      assert scene.blender_source.attached?
      asset=StudioAsset.find(result[:asset_id])
      assert asset.proxy.attached?,asset.metadata["warnings"].inspect
      assert asset.thumbnail.attached?,asset.metadata["warnings"].inspect
      assert_equal is_mesh,scene.settings["character_base_mesh"]
      assert_equal !is_mesh,scene.scene_objects.any? { |object| object.definition["native_type"]=="ARMATURE" }
      assert scene.scene_objects.exists?(object_type:"camera")
      assert_equal is_mesh ? "CC0" : "CC-BY 4.0",scene.settings.dig("source_credits",0,"license")
    end
  end

  def test_starter_cast_pins_the_uploaded_rig_and_checks_site_and_armature
    source=StudioAsset.create!(owner:@alice,site:@site,name:"Library rig",kind:"blend",status:"ready",
      request_key:SecureRandom.uuid,metadata:{"scenes"=>[{"name"=>"Rig scene","objects"=>[{"definition"=>{"native_type"=>"ARMATURE"}}]}]})
    source.native.attach(io:StringIO.new("fixture"),filename:"rig.blend",content_type:"application/x-blender",identify:false)
    character={rig:"library",asset_id:source.id}
    assert_raises(ActiveRecord::RecordNotFound) { start_cast(character:character,site_id:@other_site.id) }
    result=start_cast(character:character)
    saved=StudioAsset.find(result[:asset_id]).metadata.dig("starter_cast","character")
    assert_equal [source.id,source.native.blob.id,"Rig scene"],saved.values_at("asset_id","blob_id","scene")
    source.update!(metadata:{"scenes"=>[{"name"=>"Mesh only","objects"=>[{"definition"=>{"native_type"=>"MESH"}}]}]})
    assert_raises(ArgumentError) { start_cast(character:character) }
  end

  def test_starter_cast_reports_old_worker_and_can_retry
    id=start_cast[:asset_id]
    Studio::NativeBlender::Runtime.stub(:status,{ready:true,version:"4.0.2"}){StudioStarterCastJob.perform_now(id)}
    asset=StudioAsset.find(id);assert_equal "failed",asset.status
    assert_includes asset.error_message,"4.4"
    assert_equal id,start_cast[:asset_id];assert_equal "uploaded",asset.reload.status
  end
  def test_starter_cast_retries_the_original_delayed_asset_once
    id=start_cast[:asset_id]
    asset=StudioAsset.find(id)
    asset.update_columns(updated_at:3.minutes.ago)
    assert_equal "delayed",action("starter_scene_status",asset_id:id)[:phase]
    assert_raises(ActiveRecord::RecordNotFound){action("starter_scene_create",retry_asset_id:id,site_id:@other_site.id)}
    jobs=ActiveJob::Base.queue_adapter.enqueued_jobs.size
    assert_equal id,action("starter_scene_create",retry_asset_id:id)[:asset_id]
    assert_equal "queued",action("starter_scene_create",retry_asset_id:id)[:phase]
    assert_equal jobs+1,ActiveJob::Base.queue_adapter.enqueued_jobs.size
  end

  def test_starter_cast_uses_real_official_rigs_and_creates_a_native_project
    rain=ENV["STUDIO_STARTER_RAIN_ARCHIVE"];snow=ENV["STUDIO_STARTER_SNOW_ARCHIVE"]
    live=ENV["STUDIO_STARTER_LIVE_DOWNLOAD"]=="1"
    skip "Set the two verified official archive paths or enable live download" unless live || (rain && snow)
    id=start_cast[:asset_id]
    download=lambda do |url,path,**_args|
      source=url.include?("eea73e55") ? rain : snow
      FileUtils.cp(source,path)
    end
    Rails.stub(:root,Pathname(ROOT)) do
      if live
        StudioStarterCastJob.perform_now(id)
      else
        Studio::NativeBlender::DemoImport.stub(:download,download){StudioStarterCastJob.perform_now(id)}
      end
    end
    asset=StudioAsset.find(id);assert_equal "ready",asset.status,asset.error_message
    result=action("starter_scene_status",asset_id:id);assert_equal "ready",result[:phase]
    scene=StudioScene.find(result[:scene_id]);assert scene.blender_source.attached?
    rigs=scene.scene_objects.select{|o|o.definition["native_type"]=="ARMATURE" && o.name.start_with?("RIG-")}
    assert_equal 2,rigs.length
    assert rigs.any?{|o|o.name.downcase.include?("rain") && o.definition["bones"].length>2000}
    assert rigs.any?{|o|o.name.downcase.include?("snow") && o.definition["bones"].length>1000}
    assert scene.scene_objects.exists?(object_type:"camera")
    assert scene.scene_objects.any?{|o|o.definition["native_type"]=="LIGHT"}
    assert_equal 2,asset.metadata.dig("source","credits").length
    FileUtils.mkdir_p(File.join(ROOT,"tmp/starter-cast-proof"))
    File.open(File.join(ROOT,"tmp/starter-cast-proof/scene.blend"),"wb"){|out|asset.native.blob.download{|bytes|out.write(bytes)}}
    script=File.join(ROOT,"test/operations/starter_cast_probe.py")
    native=File.join(ROOT,"tmp/starter-cast-proof/scene.blend")
    stdout=Studio::MediaProcess.run!([ENV.fetch("BLENDER_BIN","blender"),"--background",native,"--disable-autoexec","--python-exit-code","1","--python",script],timeout:60)
    probe=JSON.parse(stdout.lines.find{|line|line.start_with?("STARTER_CAST_PROOF=")}.delete_prefix("STARTER_CAST_PROOF="))
    assert_equal 2,probe["rigs"];assert probe["drivers"].all?(&:positive?);assert_equal [true,true],probe["moving_heads"]
    scene.update!(settings:scene.settings.merge("resolution_x"=>192,"resolution_y"=>108,"fps"=>12,"frame_start"=>1,"frame_end"=>24,"samples"=>4))
    manifest=Blender::ManifestBuilder.new(scene).call;manifest["outputs"]={"blend"=>true,"animation"=>true}
    operation=scene.studio_project.studio_operations.create!(studio_scene:scene,operation_type:"build_scene",provider:"blender",capability:"studio.render.preview",status:"pending",intent:{"user_id"=>@alice.id},manifest:manifest)
    Dir.mktmpdir("starter-render-") do |folder|
      old=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=folder
      Rails.stub(:root,Pathname(ROOT)) do
        rendered=Studio::Providers::BlenderProvider.new(operation).call
        movie=rendered.output_directory.join("movie.mp4")
        assert movie.exist?
        FileUtils.cp(movie,File.join(ROOT,"tmp/starter-cast-proof/starter.mp4"))
        data=JSON.parse(Studio::MediaProcess.run!(["ffprobe","-v","error","-show_streams","-show_format","-of","json",movie.to_s]))
        assert data["streams"].any?{|stream|stream["codec_name"]=="h264"}
        assert_in_delta 2,data["format"]["duration"].to_f,0.15
      end
    ensure
      ENV["BLENDER_OUTPUT_ROOT"]=old
    end
  end
end
