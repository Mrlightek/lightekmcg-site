# frozen_string_literal: true
module Studio
  module Ai
    class InputImage
      def self.validate!(source)
        raise ArgumentError,"Choose a ready PNG, JPEG or WebP image up to 10 MB" unless source.kind=="image" && source.status=="ready" && source.proxy.attached? && %w[image/png image/jpeg image/webp].include?(source.proxy.blob.content_type) && source.proxy.blob.byte_size.between?(1,10.megabytes)
        width=source.metadata["width"].to_i;height=source.metadata["height"].to_i
        raise ArgumentError,"Use a starting image no larger than 16 megapixels" unless width>0 && height>0 && width*height<=16_777_216
      end
      def self.prepare(asset)
        raise ArgumentError,"This generation has no saved starting image" unless asset.ai_input.attached?
        raise ArgumentError,"The saved starting image exceeds 10 MB" if asset.ai_input.blob.byte_size>10.megabytes
        Studio::MediaProcess.temporary_directory("genesis-input-") do |root|
          input=File.join(root,"source");output=File.join(root,"starting.png")
          asset.ai_input.blob.open{|file|FileUtils.cp(file.path,input)}
          command=[ENV.fetch("LIGHTEK_FFMPEG","ffmpeg"),"-v","error","-y","-protocol_whitelist","file,pipe","-i",input,"-frames:v","1","-vf","scale=1280:704:force_original_aspect_ratio=increase,crop=1280:704","-pix_fmt","rgb24",output]
          if Rails.env.production?
            command=Studio::MediaProcess.container(command.map{|arg|arg.start_with?(root) ? arg.sub(root,"/work") : arg},root:root,image:Studio::NativeBlender::Runtime.image(:media))
          end
          Studio::MediaProcess.run!(command,timeout:30)
          raise ArgumentError,"Prepared starting image exceeds 10 MB" if File.size(output)>10.megabytes
          File.binread(output)
        end
      rescue StandardError=>error
        raise error if error.is_a?(ArgumentError)
        raise ArgumentError,"The starting image could not be prepared. Check media worker health and use a supported still image."
      end
    end
  end
end
