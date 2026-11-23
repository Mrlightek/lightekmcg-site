# frozen_string_literal: true
require "tmpdir"
require "fileutils"
require "digest"
class StudioStarterCastJob < ApplicationJob
  queue_as :studio
  def perform(id)
    asset=StudioAsset.find(id);claimed=false
    asset.with_lock do
      return unless asset.status=="uploaded"
      asset.update!(status:"processing",metadata:asset.metadata.merge("starter_cast"=>asset.metadata.fetch("starter_cast").merge("phase"=>"checking_worker")))
      claimed=true
    end
    source=asset.metadata.fetch("source").deep_dup
    variant=asset.metadata.dig("starter_cast","character")
    access=Studio::PwaAccess.new("user_id"=>asset.owner_id,"site_id"=>asset.site_id)
    builder=Studio::NativeBlender::StarterCast
    base=variant&.fetch("rig")
    collection=builder::BUNDLES[base]
    catalog_key=builder.catalog_key(base) if collection
    bundle=Studio::NativeBlender::DemoCatalog.fetch(catalog_key) if catalog_key
    minimum=bundle ? bundle.fetch("minimum_blender") : "4.4"
    runtime=Studio::NativeBlender::Runtime.status
    raise ArgumentError,runtime.fetch(:message,"The Blender worker is unavailable.") unless runtime[:ready]
    version=runtime[:version]
    raise ArgumentError,"The character worker needs Blender #{minimum} or newer. Deploy the current Studio runtime before retrying." unless version && Gem::Version.new(version)>=Gem::Version.new(minimum)
    sources=if collection
      []
    elsif variant&.key?("asset_id")
      record=Studio::NativeBlender::StarterCast.source_asset!(access,variant.fetch("asset_id"))
      raise ArgumentError,"The source character changed; start a new copy from the library" unless record.native.blob.id==variant["blob_id"]
      [record]
    else
      keys=variant ? [variant.fetch("rig")] : Studio::NativeBlender::StarterCast::KEYS
      keys.map { |key| import_rig(asset,key) }
    end
    Studio::MediaProcess.temporary_directory("lightek-starter-cast-") do |root|
      source_specs=sources.each_with_index.map do |record,index|
        path=File.join(root,"character-#{index}.blend")
        File.open(path,"wb"){|out|record.native.blob.download{|chunk|out.write(chunk)}}
        {"path"=>path,"name"=>record.name,"x"=>variant ? 0 : (index.zero? ? -0.65 : 0.65)}
      end
      if collection
        phase(asset,"importing_#{catalog_key}")
        source_specs << {
          "path"=>extract_bundle(bundle,root), "collection"=>collection, "name"=>bundle.fetch("name"), "x"=>0,
          "pose"=>builder::ELLIE_POSES[variant["pose"]], "require_rig"=>!builder.mesh?(base)
        }.compact
      end
      phase(asset,"building_scene")
      params={"sources"=>source_specs,"output"=>File.join(root,"starter.blend")}
      params.merge!("character"=>variant.except("asset_id","blob_id"),"name"=>asset.name,
        "credits"=>source.fetch("credits")) if variant
      script=Rails.root.join("blender/starter_cast.py")
      if Rails.env.production?
        params["sources"].each{|row|row["path"]=row["path"].sub(root,"/work")};params["output"]=params["output"].sub(root,"/work")
        FileUtils.cp(script,File.join(root,"starter_cast.py"))
        command=Studio::MediaProcess.container(["blender","--background","--factory-startup","--disable-autoexec","--python-exit-code","1","--python","/work/starter_cast.py","--","/work/params.json"],root:root,image:Studio::NativeBlender::Runtime.image)
      else
        command=[ENV.fetch("BLENDER_BIN","blender"),"--background","--factory-startup","--disable-autoexec","--python-exit-code","1","--python",script.to_s,"--",File.join(root,"params.json")]
      end
      File.write(File.join(root,"params.json"),params.to_json)
      Studio::MediaProcess.run!(command,timeout:180)
      File.open(File.join(root,"starter.blend"),"rb") do |file|
        asset.file.attach(io:file,filename:variant ? "character.blend" : "rain-and-snow.blend",content_type:"application/x-blender",identify:false)
      end
      phase(asset,"preparing_editor")
      Studio::Assets::Ingestor.call(asset,source_path:File.join(root,"starter.blend"),posed_viewport:collection.present?)
    end
    asset.update!(metadata:asset.metadata.merge("source"=>source))
    created=Studio::NativeBlender::NativeTemplate.call(access:access,payload:{"asset_id"=>asset.id,"name"=>asset.name,"request_key"=>"#{asset.request_key}-project"})
    scene=StudioScene.find(created[:scene_id]);scene.update!(settings:scene.settings.merge("source_credits"=>source.fetch("credits"),"studio_entry"=>"stage","rigged_character"=>variant.present? && !builder.mesh?(base),
      "character_base_mesh"=>builder.mesh?(base)))
    asset.update!(metadata:asset.metadata.merge("starter_cast"=>asset.metadata.fetch("starter_cast").merge("phase"=>"ready","scene_id"=>created[:scene_id],"project_id"=>created[:project_id])))
  rescue StandardError=>error
    if claimed
      asset.reload.update!(status:"failed",error_message:error.message.to_s.first(500),metadata:asset.metadata.merge("starter_cast"=>asset.metadata.fetch("starter_cast").merge("phase"=>"failed")))
    end
  end

  private

  def extract_bundle(demo,root)
    archive=File.join(root,"source.zip")
    Studio::NativeBlender::DemoImport.download(demo.fetch("url"),archive,referer:demo["source_page"])
    unless Digest::SHA256.file(archive).hexdigest==demo.fetch("sha256")
      raise ArgumentError,"The Blender bundle changed. Update its verified catalog entry before importing."
    end
    paths=JSON.parse(Studio::MediaProcess.run!(
      ["python3",Rails.root.join("blender/extract_demo.py").to_s,archive,File.join(root,"bundle")],timeout:90))
    raise ArgumentError,"The Blender bundle should contain exactly one native asset file" unless paths.one?
    paths.first
  end

  def import_rig(asset,key)
    phase(asset,"importing_#{key}")
    demo=Studio::NativeBlender::DemoCatalog.fetch(key)
    record=StudioAsset.find_or_create_by!(owner_id:asset.owner_id,request_key:"starter-source-#{asset.site_id}-#{key}") do |row|
      row.assign_attributes(site_id:asset.site_id,name:demo["name"],kind:"blend",status:"uploaded",metadata:{"demo_key"=>key,"source"=>demo})
    end
    record.with_lock { Studio::NativeBlender::DemoImport.call(record) unless record.status=="ready" && record.native.attached? }
    record
  end

  def phase(asset,value)
    asset.update!(metadata:asset.metadata.merge("starter_cast"=>asset.metadata.fetch("starter_cast").merge("phase"=>value)))
  end
end
