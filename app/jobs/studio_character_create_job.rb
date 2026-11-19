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
      FileUtils.cp(Rails.root.join("blender/create_side_views.py"),File.join(root,"create_side_views.py"))
      %w[contact_character_v1.py hand_rig_v1.py hand_surface_v1.py].each { |file|FileUtils.cp(Rails.root.join("blender",file),File.join(root,file)) }
      FileUtils.mkdir_p(File.join(root,"profiles"));FileUtils.cp(Rails.root.join("blender/profiles/contact_biped_v1.json"),File.join(root,"profiles/contact_biped_v1.json"))
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
      reach=asset.metadata.dig("performer_build","style")=="illustrated" ? %w[left right].to_h { |side| letter=side=="left" ? "L" : "R";[side,{"rig"=>"PerformerRig","upper"=>"Arm.#{letter}","forearm"=>"Forearm.#{letter}","hand"=>"Hand #{letter}","wrist_anchor"=>[0,0,0.12],"contact_anchor"=>[0,0.004,0]}] } : {}
      view_names=Array(asset.metadata["scenes"]).flat_map { |row| Array(row["objects"]) }.select { |row| row.dig("definition","native_type")=="MESH" }.map { |row| row["name"] }
      views=reach.any? ? {"version"=>1,"front"=>view_names.reject { |name| name.start_with?("Side ") },"side"=>view_names.select { |name| name.start_with?("Side ") }} : nil
      physical=asset.metadata.dig("performer_build","style")=="physical"
      if physical
        bones={"head"=>{"object"=>"ContactRig","bone"=>"Part.head"},"left_arm"=>{"object"=>"ContactRig","bone"=>"Part.upperL"},"right_arm"=>{"object"=>"ContactRig","bone"=>"Part.upperR"}}
      end
      profile=Studio::Performance::Cast.profile(asset,{"source_scene"=>"Lightek Performer","bindings"=>bindings,"bones"=>bones,"reach_bindings"=>reach,"views"=>views,"attention_binding"=>(physical ? {"rig"=>"ContactRig","head"=>"Part.head","eye_anchor"=>[0.09,0,0]} : {"rig"=>"PerformerRig","head"=>"Head","eye_anchor"=>[0,-0.317,1.99]}),"mechanics"=>(physical ? Studio::Performance::VerifiedGrasp::BINDINGS : asset.metadata.dig("performer_build","style")=="illustrated" ? Studio::Performance::Mechanics.bindings : nil)})
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
