# frozen_string_literal: true
require_relative "studio_library_checks"
require File.join(ROOT,"app/services/studio/spatial/runtime")
require File.join(ROOT,"app/services/studio/spatial/generation")
require File.join(ROOT,"app/jobs/studio_spatial_generation_job")
class SpatialGenerationTest < StudioLibraryTest
  StudioLibraryTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def test_generation_submission_is_idempotent_and_does_not_expose_credentials
    access=Studio::PwaAccess.new("user_id"=>@alice.id,"site_id"=>@site.id)
    Studio::Spatial::Generation.stub(:credential,{"api_key"=>"private-test-key"}) do
      first=Studio::Spatial::Generation.submit(access:access,scene_id:@scene.id,prompt:"A brass lamp",request_key:"generation-test-123")
      second=Studio::Spatial::Generation.submit(access:access,scene_id:@scene.id,prompt:"A brass lamp",request_key:"generation-test-123")
      assert_equal first.id,second.id;refute_includes Studio::Spatial::Generation.status(first).to_json,"private-test-key"
      assert_raises(ArgumentError){Studio::Spatial::Generation.submit(access:access,scene_id:@scene.id,prompt:"Different lamp",request_key:"generation-test-123")}
    end
  end
  def test_real_optimization_import_and_camera_staging_after_provider_result
    skip "Set LIGHTEK_TEST_BLENDER=1" unless ENV["LIGHTEK_TEST_BLENDER"]=="1"
    access=Studio::PwaAccess.new("user_id"=>@alice.id,"site_id"=>@site.id)
    Studio::Spatial::Generation.stub(:credential,{"api_key"=>"test-key"}) do
      asset=Studio::Spatial::Generation.submit(access:access,scene_id:@scene.id,prompt:"A test cube",request_key:"real-generation-123")
      original=Studio::MediaProcess.method(:run!)
      process=->(command,**options){
        if command.include?("services.spatial.download")
          payload=JSON.parse(options.fetch(:stdin_data));FileUtils.cp(ENV.fetch("STUDIO_VIEWPORT_FIXTURE","/tmp/native-viewport-proof.glb"),payload.fetch("output"));""
        else original.call(command,**options)
        end
      }
      provider=->(path,_key,**_options){path.start_with?("generation/") ? {"task_id"=>"existing-provider-task"} : {"status"=>"success","output"=>{"model_url"=>"https://cdn.tripo3d.ai/model.glb"}}}
      Rails.stub(:root,Pathname.new(ROOT)) do
        Studio::Spatial::Generation.stub(:provider,provider) do
          Studio::MediaProcess.stub(:run!,process){StudioSpatialGenerationJob.perform_now(asset.id)}
        end
      end
      asset.reload;assert_equal "ready",asset.status,asset.error_message
      assert asset.file.attached?;assert asset.proxy.attached?
      object=@scene.scene_objects.find(asset.metadata.dig("generation","object_id"));assert_equal asset.id,object.definition["asset_id"]
      assert object.definition["scale"].all? { |value| value>0 };assert_equal "ready",asset.metadata.dig("generation","phase")
      count=@scene.scene_objects.count;StudioSpatialGenerationJob.perform_now(asset.id);assert_equal count,@scene.scene_objects.count
    end
  end
end
