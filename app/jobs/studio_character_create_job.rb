require "tmpdir"
require "fileutils"
class StudioCharacterCreateJob < ApplicationJob
  queue_as :studio
  def perform(id)
    asset=StudioAsset.find(id)
    asset.with_lock do
      return if asset.metadata["character_profile"] && asset.status=="ready"
      raise ArgumentError,"Not a Studio performer build" unless asset.metadata["performer_build"]
      asset.update!(status:"processing",error_message:nil)
    end
    Dir.mktmpdir("lightek-performer-") do |root|
      FileUtils.cp(Rails.root.join("blender/create_performer.py"),File.join(root,"create_performer.py"))
      File.write(File.join(root,"params.json"),asset.metadata.fetch("performer_build").to_json)
      output=File.join(root,"performer.blend")
      command=[ENV.fetch("BLENDER_BIN","blender"),"--background","--factory-startup","--disable-autoexec","--python-exit-code","1","--python",File.join(root,"create_performer.py"),"--",File.join(root,"params.json"),output]
      if Rails.env.production?
        command=command.map{|value|value.gsub(root,"/work")}
        command=Studio::MediaProcess.container(command,root:root,image:Studio::NativeBlender::Runtime.image)
      end
      Studio::MediaProcess.run!(command,timeout:90)
      asset.file.attach(io:File.open(output),filename:"performer.blend",content_type:"application/x-blender")
      Studio::Assets::Ingestor.call(asset)
      bindings={"jaw_open"=>{"object"=>"FaceMouth","key"=>"jaw_open"},"smile"=>{"object"=>"FaceMouth","key"=>"smile"},"mouth_wide"=>{"object"=>"FaceMouth","key"=>"mouth_wide"},"mouth_round"=>{"object"=>"FaceMouth","key"=>"mouth_round"},"blink"=>{"object"=>"FaceEyes","key"=>"blink"},"brow_raise"=>{"object"=>"FaceBrows","key"=>"brow_raise"}}
      bones={"head"=>{"object"=>"PerformerRig","bone"=>"Head"},"left_arm"=>{"object"=>"PerformerRig","bone"=>"Arm.L"},"right_arm"=>{"object"=>"PerformerRig","bone"=>"Arm.R"}}
      profile=Studio::Performance::Cast.profile(asset,{"source_scene"=>"Lightek Performer","bindings"=>bindings,"bones"=>bones})
      asset.update!(metadata:asset.metadata.merge("character_profile"=>profile))
    end
  rescue StandardError=>error
    asset&.update!(status:"failed",error_message:error.message.to_s.first(1000))
    raise
  end
end
