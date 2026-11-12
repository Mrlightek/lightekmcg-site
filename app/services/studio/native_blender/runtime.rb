# frozen_string_literal: true
module Studio
  module NativeBlender
    class Runtime
      DEFAULT_IMAGE="lightek/studio-media:20261112".freeze
      def self.image(role=:asset)
        ENV[{render:"STUDIO_RENDER_WORKER_IMAGE",media:"STUDIO_MEDIA_WORKER_IMAGE"}.fetch(role,"STUDIO_ASSET_WORKER_IMAGE")].presence || ENV["STUDIO_ASSET_WORKER_IMAGE"].presence || DEFAULT_IMAGE
      end
      def self.status
        if Rails.env.production?
          output=Studio::MediaProcess.run!(["docker","run","--rm","--name","lightek-blender-health-#{SecureRandom.hex(8)}",
            "--network","none","--read-only","--cap-drop","ALL","--security-opt","no-new-privileges",
            "--pids-limit","128","--memory","2g","--cpus",Studio::MediaProcess.cpu_limit,"--user","#{Process.uid}:#{Process.gid}",
            "--tmpfs","/tmp:rw,nosuid,size=512m",image,"blender","--background","--factory-startup","--disable-autoexec",
            "--python-exit-code","1","--python-expr",'import bpy, numpy; assert bpy.app.version >= (4, 4, 0); print("LIGHTEK_BLENDER_RUNTIME_READY=" + bpy.app.version_string)'],timeout:20)
          version=output.lines.find { |line| line.start_with?("LIGHTEK_BLENDER_RUNTIME_READY=") }&.strip&.split("=",2)&.last
          raise "Blender startup was not confirmed" if version.blank?
          {ready:true,message:"Blender #{version} ready",version:version,image:image}
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
