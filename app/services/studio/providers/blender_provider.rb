module Studio
  module Providers
    class BlenderProvider
      OUTPUTS = {
        "scene.blend" => "blend",
        "scene.glb" => "glb",
        "preview.png" => "preview",
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

        result = Blender::Runner.new(operation).call
        attach_outputs(result.output_directory)
        result
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
          ".json" => "application/json",
          ".glb" => "model/gltf-binary",
          ".blend" => "application/octet-stream",
          ".log" => "text/plain"
        }.fetch(File.extname(filename), "application/octet-stream")
      end
    end
  end
end
