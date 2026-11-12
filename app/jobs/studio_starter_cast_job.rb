# frozen_string_literal: true
require "tmpdir"
require "fileutils"
class StudioStarterCastJob < ApplicationJob
  queue_as :studio
  def perform(id)
    asset=StudioAsset.find(id);claimed=false
    asset.with_lock do
      return unless asset.status=="uploaded"
      asset.update!(status:"processing",metadata:asset.metadata.merge("starter_cast"=>asset.metadata.fetch("starter_cast").merge("phase"=>"checking_worker")))
      claimed=true
    end
    runtime=Studio::NativeBlender::Runtime.status
    version=runtime[:version] || runtime[:message].to_s[/\d+\.\d+(?:\.\d+)?/]
    raise ArgumentError,"The character worker needs Blender 4.4 or newer. Deploy the current Studio runtime before retrying." unless runtime[:ready] && version && Gem::Version.new(version)>=Gem::Version.new("4.4")
    source=asset.metadata.fetch("source").deep_dup
    sources=Studio::NativeBlender::StarterCast::KEYS.map do |key|
      phase(asset,"importing_#{key}")
      demo=Studio::NativeBlender::DemoCatalog.fetch(key)
      record=StudioAsset.find_or_create_by!(owner_id:asset.owner_id,request_key:"starter-source-#{asset.site_id}-#{key}") do |row|
        row.assign_attributes(site_id:asset.site_id,name:demo["name"],kind:"blend",status:"uploaded",metadata:{"demo_key"=>key,"source"=>demo})
      end
      record.with_lock {Studio::NativeBlender::DemoImport.call(record) unless record.status=="ready" && record.native.attached?}
      record
    end
    phase(asset,"building_scene")
    Studio::MediaProcess.temporary_directory("lightek-starter-cast-") do |root|
      params={"sources"=>sources.each_with_index.map do |record,index|
        path=File.join(root,"character-#{index}.blend")
        File.open(path,"wb"){|out|record.native.blob.download{|chunk|out.write(chunk)}}
        {"path"=>path,"name"=>record.name,"x"=>index.zero? ? -0.65 : 0.65}
      end,"output"=>File.join(root,"starter.blend")}
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
      asset.file.attach(io:File.open(File.join(root,"starter.blend")),filename:"rain-and-snow.blend",content_type:"application/x-blender",identify:false)
      phase(asset,"preparing_editor")
      Studio::Assets::Ingestor.call(asset)
    end
    asset.update!(metadata:asset.metadata.merge("source"=>source))
    access=Studio::PwaAccess.new("user_id"=>asset.owner_id,"site_id"=>asset.site_id)
    created=Studio::NativeBlender::NativeTemplate.call(access:access,payload:{"asset_id"=>asset.id,"name"=>asset.name,"request_key"=>"#{asset.request_key}-project"})
    scene=StudioScene.find(created[:scene_id]);scene.update!(settings:scene.settings.merge("source_credits"=>source.fetch("credits")))
    asset.update!(metadata:asset.metadata.merge("starter_cast"=>asset.metadata.fetch("starter_cast").merge("phase"=>"ready","scene_id"=>created[:scene_id],"project_id"=>created[:project_id])))
  rescue StandardError=>error
    if claimed
      asset.reload.update!(status:"failed",error_message:error.message.to_s.first(500),metadata:asset.metadata.merge("starter_cast"=>asset.metadata.fetch("starter_cast").merge("phase"=>"failed")))
    end
  end
  private
  def phase(asset,value)
    asset.update!(metadata:asset.metadata.merge("starter_cast"=>asset.metadata.fetch("starter_cast").merge("phase"=>value)))
  end
end
