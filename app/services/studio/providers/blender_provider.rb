require "tmpdir"

module Studio
  module Providers
    class BlenderProvider
      OUTPUTS = {
        "scene.blend" => "blend",
        "project.zip" => "package",
        "scene.glb" => "glb",
        "preview.png" => "preview",
        "movie.mp4" => "video",
        "authoring.json" => "authoring",
        "manifest.json" => "manifest",
        "blender.log" => "log"
      }.freeze

      def initialize(operation)
        @operation = operation
      end

      def call
        unless operation.operation_type == "build_scene"
          raise ArgumentError, "Blender provider does not support #{operation.operation_type.inspect} yet"
        end

        Studio::MediaProcess.temporary_directory("lightek-scene-assets-") do |root|
          actor_id=operation.intent["user_id"] || operation.studio_project.owner_id
          access=Studio::PwaAccess.new("user_id"=>actor_id,"site_id"=>operation.studio_project.site_id)
          access.projects.find(operation.studio_project_id)
          objects=Array(operation.manifest.dig("scene","objects"))
          ids=objects.select { |object| object["type"]=="imported_asset" && !object.dig("definition","native_source_preview") }.map { |object| object.dig("definition","asset_id").to_i }.uniq
          paths={}
          performance_paths={}
          ids.each do |id|
            asset=StudioAsset.for_actor(access).where(status:"ready").find(id)
            native=asset.kind=="blend" && asset.native.attached?
            attachment=native ? asset.native : asset.proxy
            profile=objects.find { |object| object.dig("definition","asset_id").to_i==id && object.dig("definition","character_profile") }&.dig("definition","character_profile")
            if profile
              pinned=operation.performance_sources.find { |source| source.blob_id==profile["source_blob_id"] }
              raise ArgumentError,"The character source snapshot is unavailable" unless pinned
              attachment=pinned;native=true
            end
            raise ArgumentError,"Asset source is not ready" unless attachment && (attachment.respond_to?(:attached?) ? attachment.attached? : attachment.persisted?)
            extension=native ? "blend" : "glb"
            path=File.join(root,"#{id}.#{extension}")
            File.open(path,"wb") { |file| attachment.blob.download { |chunk| file.write(chunk) } }
            paths[id]={path:path,format:extension,scene:asset.metadata["source_scene"]}
          end
          objects.each do |object|
            take=object.dig("definition","performance");next unless take
            audio=StudioAsset.for_actor(access).where(status:"ready",kind:%w[audio video]).find(take.fetch("audio_asset_id"))
            pinned=operation.performance_sources.find { |source| source.blob_id==take["audio_blob_id"] }
            raise ArgumentError,"The performance recording snapshot is unavailable" unless pinned
            path=File.join(root,"voice-#{pinned.blob_id}#{File.extname(pinned.filename.to_s)}")
            File.open(path,"wb") { |file| pinned.blob.download { |chunk| file.write(chunk) } }
            performance_paths[pinned.blob_id]=path
          end
          template_path=nil
          bundle_path=nil
          if (id=operation.manifest.dig("scene","settings","native_blender_asset_id"))
            source=operation.blender_source if operation.blender_source.attached?
            source||=operation.studio_scene.blender_source if operation.studio_scene&.blender_source&.attached?
            unless source
              asset=StudioAsset.for_actor(access).where(status:"ready",kind:"blend").find(id)
              raise ArgumentError,"Native Blender template source is unavailable" unless asset.native.attached?
              raise ArgumentError,"Native template has missing dependencies" if Array(asset.metadata["missing_dependencies"]).any?
              scene_name=operation.manifest.dig("scene","settings","native_scene")
              raise ArgumentError,"Native Blender scene is unavailable" unless Array(asset.metadata["scenes"]).any? { |scene| scene["name"]==scene_name }
              source=asset.native
            end
            bundle=operation.blender_bundle if operation.blender_bundle.attached?
            bundle||=operation.studio_scene.blender_bundle if operation.studio_scene&.blender_bundle&.attached?
            bundle||=asset.bundle if defined?(asset) && asset && asset.bundle.attached?
            if bundle
              bundle_path=File.join(root,"native-bundle.zip")
              File.open(bundle_path,"wb") { |file| bundle.blob.download { |chunk| file.write(chunk) } }
            end
            template_path=File.join(root,"native-template.blend")
            File.open(template_path,"wb") { |file| source.blob.download { |chunk| file.write(chunk) } }
          end
          result = ::Blender::Runner.new(operation,asset_paths:paths,template_path:template_path,template_bundle:bundle_path,performance_paths:performance_paths).call
          attach_outputs(result.output_directory)
          result
        end
      end

      private

      attr_reader :operation

      def attach_outputs(directory)
        OUTPUTS.each do |filename, kind|
          path = directory.join(filename)
          next unless path.exist?

          artifact = operation.artifacts.create!(kind: kind, filename: filename)
          artifact.file.attach(
            io: File.open(path),
            filename: filename,
            content_type: content_type_for(filename)
          )
        end
      end

      def content_type_for(filename)
        {
          ".png" => "image/png",
          ".mp4" => "video/mp4",
          ".zip" => "application/zip",
          ".json" => "application/json",
          ".glb" => "model/gltf-binary",
          ".blend" => "application/octet-stream",
          ".log" => "text/plain"
        }.fetch(File.extname(filename), "application/octet-stream")
      end
    end
  end
end
