require "tmpdir"
require "fileutils"
class StudioCharacterCreateJob < ApplicationJob
  queue_as :studio
  def perform(id)
    asset=StudioAsset.find(id)
    claimed=false
    asset.with_lock do
      return if asset.metadata["character_profile"] || asset.metadata["performer_phase"]=="building"
      raise ArgumentError,"Not a Studio performer build" unless asset.metadata["performer_build"]
      asset.update!(status:"processing",error_message:nil,metadata:asset.metadata.merge("performer_phase"=>"building"))
      claimed=true
    end
    Dir.mktmpdir("lightek-performer-") do |root|
      FileUtils.cp(Rails.root.join("blender/create_performer.py"),File.join(root,"create_performer.py"))
      File.write(File.join(root,"params.json"),asset.metadata.fetch("performer_build").to_json)
      prepare_photo(asset,root) if asset.character_photo.attached?
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
      %w[a b c d e f g h x].each{|shape|bindings["viseme_#{shape}"]={"object"=>"FaceMouth","key"=>"viseme_#{shape}"}}
      bones={"head"=>{"object"=>"PerformerRig","bone"=>"Head"},"left_arm"=>{"object"=>"PerformerRig","bone"=>"Arm.L"},"right_arm"=>{"object"=>"PerformerRig","bone"=>"Arm.R"}}
      profile=Studio::Performance::Cast.profile(asset,{"source_scene"=>"Lightek Performer","bindings"=>bindings,"bones"=>bones})
      asset.update!(metadata:asset.metadata.merge("character_profile"=>profile,"performer_phase"=>"ready"))
    end
  rescue StandardError=>error
    if claimed
      asset.update!(status:"failed",error_message:error.message.to_s.first(1000),
        metadata:asset.metadata.merge("performer_phase"=>"failed"))
    end
    raise
  end

  private

  def prepare_photo(asset, root)
    source=File.join(root,"photo-input")
    output=File.join(root,"portrait.png")
    asset.character_photo.blob.open { |image| FileUtils.cp(image.path,source) }
    command=[ENV.fetch("LIGHTEK_FFMPEG","ffmpeg"),"-v","error","-y","-protocol_whitelist","file,pipe",
      "-max_pixels","16777216","-i",source,"-frames:v","1","-vf",
      "crop='min(iw,ih)':'min(iw,ih)':exact=1,scale=512:512,setsar=1","-pix_fmt","rgb24",output]
    if Rails.env.production?
      command=command.map { |argument| argument.start_with?(root) ? argument.sub(root,"/work") : argument }
      command=Studio::MediaProcess.container(command,root:root,image:Studio::NativeBlender::Runtime.image(:media))
    end
    Studio::MediaProcess.run!(command,timeout:30)
    raise ArgumentError,"Choose a clear portrait photo" unless File.file?(output) && File.size(output)>0
  rescue StandardError
    raise ArgumentError,"This photo could not be read. Choose a JPEG, PNG or WebP under 16 megapixels."
  end

end
