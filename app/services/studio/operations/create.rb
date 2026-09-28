module Studio
  module Operations
    class Create
      def self.build_scene!(scene:, requested_by: nil, intent: {})
        project = scene.studio_project
        manifest = Blender::ManifestBuilder.new(scene).call

        project.studio_operations.create!(
          production: scene.production,
          studio_scene: scene,
          operation_type: "build_scene",
          provider: "blender",
          capability: "studio.scene.build",
          status: "pending",
          intent: intent.merge("requested_by" => requested_by.to_s).compact,
          manifest: manifest
        )
      end
    end
  end
end
