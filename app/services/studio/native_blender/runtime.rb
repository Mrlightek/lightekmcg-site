# frozen_string_literal: true
module Studio
  module NativeBlender
    class Runtime
      DEFAULT_IMAGE="lightek/studio-media:20261101".freeze
      def self.image(role=:asset)
        ENV[{render:"STUDIO_RENDER_WORKER_IMAGE",media:"STUDIO_MEDIA_WORKER_IMAGE"}.fetch(role,"STUDIO_ASSET_WORKER_IMAGE")].presence || ENV["STUDIO_ASSET_WORKER_IMAGE"].presence || DEFAULT_IMAGE
      end
      def self.status
        if Rails.env.production?
          Studio::MediaProcess.run!(["docker","image","inspect",image],timeout:8)
          {ready:true,message:"Blender worker installed",image:image}
        else
          version=Studio::MediaProcess.run!([ENV.fetch("BLENDER_BIN","blender"),"--version"],timeout:8).lines.first.to_s.strip
          {ready:true,message:version}
        end
      rescue StandardError
        {ready:false,message:"The Blender worker is unavailable. The deployment must install the Studio media runtime before native imports and renders can run.",image:image}
      end
    end
  end
end
