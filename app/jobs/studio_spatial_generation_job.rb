# frozen_string_literal: true
class StudioSpatialGenerationJob < ApplicationJob
  queue_as :studio
  def perform(id)
    asset=StudioAsset.find(id);claimed=false
    asset.with_lock do
      return unless asset.status=="uploaded"
      generation=asset.metadata.fetch("generation")
      asset.update!(status:"processing",metadata:asset.metadata.merge("generation"=>generation.merge("phase"=>generation["task_id"] ? "generating" : "submitting")))
      claimed=true
    end
    access=Studio::PwaAccess.new("user_id"=>asset.owner_id,"site_id"=>asset.site_id)
    scene=access.scene!(asset.metadata.dig("generation","scene_id"))
    generation=asset.metadata.fetch("generation").deep_dup
    unless asset.file.attached?
      update_generation(asset,generation.merge("phase"=>"configuration"))
      key=Studio::Spatial::Generation.credential(asset.site_id).fetch("api_key")
      unless generation["task_id"]
        update_generation(asset,generation.merge("phase"=>"submitting"))
        result=Studio::Spatial::Generation.provider("generation/text-to-model",key,payload:{prompt:generation.fetch("prompt"),model:"v3.1-20260211",texture:true,pbr:true})
        generation["task_id"]=result.fetch("task_id")
        raise ArgumentError,"Invalid provider task ID" unless generation["task_id"].match?(/\A[a-zA-Z0-9_-]{1,150}\z/)
        update_generation(asset,generation.merge("phase"=>"generating"))
      end
      result=nil
      150.times do
        result=Studio::Spatial::Generation.provider("tasks/#{generation.fetch('task_id')}",key)
        break if result["status"]=="success"
        raise ArgumentError,"Provider generation #{result['status']}" if %w[failed cancelled banned].include?(result["status"])
        sleep 2
      end
      raise ArgumentError,"Generation timed out; retry resumes the existing provider task" unless result["status"]=="success"
      update_generation(asset,generation.merge("phase"=>"downloading"))
      Dir.mktmpdir("lightek-generated-") do |root|
        output=File.join(root,"original.glb")
        Studio::MediaProcess.run!([Studio::Spatial::Runtime.fetch("STUDIO_SPATIAL_PYTHON","python3"),"-m","services.spatial.download"],timeout:100,
          stdin_data:{url:result.fetch("output").fetch("model_url"),output:output,allowed_hosts:%w[cdn.tripo3d.ai cdn.tripo3d.com]}.to_json)
        asset.file.attach(io:File.open(output),filename:"generated-#{asset.id}.glb",content_type:"model/gltf-binary")
      end
    end
    update_generation(asset,generation.merge("phase"=>"optimizing"))
    Dir.mktmpdir("lightek-stage-") do |root|
      source=File.join(root,"source.glb");File.open(source,"wb") { |file| asset.file.blob.download { |chunk| file.write(chunk) } }
      optimized=File.join(root,"optimized.glb");blender(root,"spatial_optimize.py",[source,optimized])
      Studio::Assets::Ingestor.call(asset,source_path:optimized)
      # Ingestor marks ready; keep generation processing until scene placement is durable.
      asset.update!(status:"processing");update_generation(asset,generation.merge("phase"=>"staging"))
      asset.proxy.blob.open do |proxy|
        FileUtils.cp(proxy.path,File.join(root,"stage.glb"))
      end
      scene.reload;revision=scene.lock_version
      manifest=Blender::ManifestBuilder.new(scene).call
      manifest["scene"]["objects"].select! { |object| object["type"]=="camera" }
      manifest["scene"]["settings"]=manifest["scene"]["settings"].except("native_blender_asset_id","native_scene","native_preserve","blender_presets")
      File.write(File.join(root,"camera.json"),manifest.to_json)
      blender(root,"spatial_place.py",[File.join(root,"camera.json"),File.join(root,"stage.glb"),File.join(root,"placement.json")])
      placement=JSON.parse(File.read(File.join(root,"placement.json")))
      scene.with_lock do
        raise ArgumentError,"Scene changed during staging; retry to fit the asset to the current camera" unless scene.lock_version==revision
        existing=scene.scene_objects.find { |object| object.definition["generation_asset_id"]==asset.id }
        object=existing || scene.scene_objects.create!(name:asset.name,object_type:"imported_asset",position:scene.scene_objects.maximum(:position).to_i+1,
          definition:placement.merge("asset_id"=>asset.id,"generation_asset_id"=>asset.id,"category"=>"prop","asset_proxy_url"=>"/api/lightek/pwa/assets/#{asset.id}/proxy","staging_anchors"=>true))
        scene.update!(settings:scene.settings.merge("generation_revision"=>scene.settings.fetch("generation_revision",0)+1)) unless existing
        generation.merge!("phase"=>"ready","object_id"=>object.id,"scene_revision"=>scene.lock_version)
      end
    end
    asset.update!(status:"ready",error_message:nil,metadata:asset.metadata.merge("generation"=>generation,"source"=>{"name"=>"Generated with Tripo","task_id"=>generation["task_id"],"provider"=>"tripo"}))
  rescue StandardError => error
    if claimed
      message=error.message.to_s
      if asset.metadata.dig("generation","phase")=="submitting" && !asset.metadata.dig("generation","task_id")
        message+=" · Provider submission needs reconciliation. Check Tripo task history before starting another generation."
      end
      asset.update!(status:"failed",error_message:message.first(600))
    end
  end
  private
  def update_generation(asset,generation)=asset.update!(metadata:asset.metadata.merge("generation"=>generation))
  def blender(root,script,args)
    if Rails.env.production?
      command=Studio::MediaProcess.container(["blender","--background","--factory-startup","--disable-autoexec","--python-exit-code","1","--python","/engine/#{script}","--",*args.map { |path| path.sub(root,"/work") }],root:root,image:Studio::NativeBlender::Runtime.image)
      index=command.index(Studio::NativeBlender::Runtime.image);command.insert(index,"-v","#{Rails.root.join('blender')}:/engine:ro")
    else
      command=[ENV.fetch("BLENDER_BIN","blender"),"--background","--factory-startup","--disable-autoexec","--python-exit-code","1","--python",Rails.root.join("blender",script).to_s,"--",*args]
    end
    Studio::MediaProcess.run!(command,timeout:240)
  end
end
