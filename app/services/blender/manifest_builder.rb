module Blender
  class ManifestBuilder
    SCHEMA_VERSION = "1.0".freeze

    def initialize(scene)
      @scene = scene
    end

    def call
      {
        "schema_version" => SCHEMA_VERSION,
        "project" => {
          "id" => scene.studio_project_id,
          "name" => scene.studio_project.name
        },
        "scene" => {
          "id" => scene.id,
          "name" => scene.name,
          "settings" => scene.settings,
          "objects" => scene.scene_objects.map { |object| serialize_object(object) }
        },
        "outputs" => {
          "blend" => true,
          "glb" => true,
          "preview" => true
        }
      }
    end

    private

    attr_reader :scene

    def serialize_object(object)
      {
        "id" => object.id,
        "name" => object.name,
        "type" => object.object_type,
        "definition" => object.definition
      }
    end
  end
end
