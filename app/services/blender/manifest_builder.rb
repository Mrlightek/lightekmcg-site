module Blender
  class ManifestBuilder
    SCHEMA_VERSION = "1.0".freeze

    def initialize(scene)
      @scene = scene
    end

    def call
      {
        "schema_version" => SCHEMA_VERSION,
        "credits" => source_credits,
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
          "bundle" => scene.blender_bundle.attached?,
          "glb" => scene.settings["native_blender_asset_id"].blank?,
          "preview" => true
        }
      }
    end

    private

    attr_reader :scene

    def source_credits
      credits=Array(scene.settings["source_credits"])
      ids=scene.scene_objects.where(object_type:"imported_asset").reject { |object| object.definition["native_source_preview"] }.map { |object| object.definition["asset_id"] }.compact
      ids<<scene.settings["native_blender_asset_id"] if credits.empty? && scene.settings["native_blender_asset_id"]
      (credits+StudioAsset.where(id:ids).flat_map { |asset| Array(asset.metadata["source_credits"])+[asset.metadata["source"]].compact }).uniq
    end

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
