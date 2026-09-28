module Studio
  module Director
    class Request
      def self.create!(scene:, instruction:, requested_by: nil)
        raise ArgumentError, "instruction is required" if instruction.to_s.strip.empty?

        scene.studio_project.studio_operations.create!(
          production: scene.production,
          studio_scene: scene,
          operation_type: "direct_scene",
          provider: "nevaeh",
          capability: "studio.direct.scene",
          status: "awaiting_planning",
          intent: {
            "instruction" => instruction.to_s.strip,
            "requested_by" => requested_by.to_s
          },
          manifest: {}
        )
      end
    end
  end
end
