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
  def test_starter_cast_reports_old_worker_and_can_retry
    id=start_cast[:asset_id]
    Studio::NativeBlender::Runtime.stub(:status,{ready:true,version:"4.0.2"}){StudioStarterCastJob.perform_now(id)}
    asset=StudioAsset.find(id);assert_equal "failed",asset.status
    assert_includes asset.error_message,"4.4"
    assert_equal id,start_cast[:asset_id];assert_equal "uploaded",asset.reload.status
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
