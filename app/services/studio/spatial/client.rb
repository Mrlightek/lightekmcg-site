# frozen_string_literal: true
require "net/http"
require "securerandom"
module Studio
  module Spatial
    class Client
      def initialize(access)
        @access=access
      end
      def create(scene)
        id=SecureRandom.uuid
        root=Pathname(ENV.fetch("STUDIO_SPATIAL_ROOT",Rails.root.join("tmp/studio-spatial").to_s)).join(id)
        FileUtils.mkdir_p(root,mode:0700)
        manifest=Blender::ManifestBuilder.new(scene).call
        manifest["revision"]=scene.lock_version
        manifest.delete("native_template_path")
        manifest.fetch("scene").fetch("objects").each do |object|
          definition=object.fetch("definition");definition.delete("asset_path")
          next unless object["type"]=="imported_asset" && !definition["native_source_preview"]
          asset=StudioAsset.for_actor(@access).where(status:"ready").find(definition.fetch("asset_id"))
          native=asset.kind=="blend" && asset.native.attached?
          attachment=native ? asset.native : asset.proxy
          raise ArgumentError,"Prepare the asset in Library before opening the Blender stream" unless attachment.attached?
          name="asset-#{asset.id}.#{native ? 'blend' : 'glb'}"
          download(attachment,root.join(name));definition.merge!("asset_path"=>name,"asset_format"=>native ? "blend" : "glb","asset_scene"=>asset.metadata["source_scene"])
        end
        if (asset_id=scene.settings["native_blender_asset_id"])
          asset=StudioAsset.for_actor(@access).where(status:"ready",kind:"blend").find(asset_id)
          raise ArgumentError,"Native template dependencies are missing" if Array(asset.metadata["missing_dependencies"]).any?
          source=scene.blender_source.attached? ? scene.blender_source : asset.native
          raise ArgumentError,"Native Blender source is unavailable" unless source.attached?
          bundle=scene.blender_bundle.attached? ? scene.blender_bundle : asset.bundle
          path=root.join("native-source.blend")
          if bundle.attached?
            archive=root.join("bundle.zip");download(bundle,archive)
            base=root.join("bundle")
            Studio::MediaProcess.run!(["python3",Rails.root.join("blender/extract_demo.py").to_s,archive.to_s,base.to_s],timeout:90)
            relative=scene.settings["native_bundle_path"].to_s
            path=base.join(relative).cleanpath
            raise ArgumentError,"Native bundle source path is invalid" if relative.empty? || !path.to_s.start_with?(base.to_s+"/") || path.extname!=".blend"
          end
          download(source,path);manifest["native_template_path"]=path.relative_path_from(root).to_s
        end
        request("/sessions",{session_id:id,user_id:@access.user.id,site_id:@access.site_id,manifest:manifest})
      rescue StandardError
        FileUtils.rm_rf(root) if root
        raise
      end
      def ticket(id)=request("/sessions/#{uuid(id)}/ticket",{user_id:@access.user.id,site_id:@access.site_id})
      def close(id)=request("/sessions/#{uuid(id)}/close",{user_id:@access.user.id,site_id:@access.site_id})
      private
      def uuid(id)
        raise ArgumentError,"Invalid Blender session" unless id.to_s.match?(/\A[0-9a-f-]{36}\z/)
        id
      end
      def download(attachment,path)
        FileUtils.mkdir_p(path.dirname)
        File.open(path,"wb",0600) { |file| attachment.blob.download { |chunk| file.write(chunk) } }
      end
      def request(path,payload)
        secret=ENV["STUDIO_SPATIAL_SECRET"]
        raise ArgumentError,"The Blender streaming service is not configured on this instance" if secret.to_s.length<32
        uri=URI(ENV.fetch("STUDIO_SPATIAL_URL","http://127.0.0.1:8095")+path)
        raise ArgumentError,"Blender service must use loopback HTTP" unless %w[127.0.0.1 localhost].include?(uri.host) && uri.scheme=="http"
        http=Net::HTTP.new(uri.host,uri.port,nil);http.open_timeout=3;http.read_timeout=60
        response=http.post(uri.request_uri,payload.to_json,{"Content-Type"=>"application/json","Authorization"=>"Bearer #{secret}"})
        raise ArgumentError,"Blender service: #{response.body.to_s.truncate(300)}" unless response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)
      rescue Errno::ECONNREFUSED,Net::OpenTimeout,Net::ReadTimeout
        raise ArgumentError,"Blender streaming worker is unavailable on this instance"
      end
    end
  end
end
