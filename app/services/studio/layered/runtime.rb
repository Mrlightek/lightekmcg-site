# frozen_string_literal: true
module Studio
  module Layered
    module Runtime
      def self.status
        image=Studio::NativeBlender::Runtime.image(:media)
        Rails.cache.fetch(["studio-layered-runtime-v3",image],expires_in:60.seconds) do
          Studio::MediaProcess.temporary_directory("layered-health-") do |root|
            File.write(File.join(root,"probe.svg"),'<svg xmlns="http://www.w3.org/2000/svg" width="2" height="2"><rect width="2" height="2" fill="red"/></svg>')
            [["ffmpeg","-v","error","-y","-protocol_whitelist","file,pipe","-i",File.join(root,"probe.svg"),"-frames:v","1",File.join(root,"probe.png")],["convert",File.join(root,"probe.png"),"-resize","1x1!",File.join(root,"check.png")],["ffmpeg","-v","error","-y","-i",File.join(root,"probe.png"),"-frames:v","1","-c:v","libx264","-threads","1","-pix_fmt","yuv420p",File.join(root,"check.mp4")]].each do |command|
              command=Studio::MediaProcess.container(command.map { |part| part.sub(root,"/work") },root:root,image:image,memory:"128m",pull:false) if Rails.env.production?
              Studio::MediaProcess.run!(command,timeout:10)
            end
          end
          {ready:true,message:"2D compositor tools available. Rendering uses the Studio worker queue.",engine:"lightek_2d"}
        rescue StandardError
          {ready:false,message:"The Studio media worker needs FFmpeg with SVG decoding and ImageMagick. Check the deployed media runtime and worker access.",engine:"lightek_2d"}
        end
      end
    end
  end
end
