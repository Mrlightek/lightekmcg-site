# frozen_string_literal: true

class RegisterStudioSceneObjectPwaCapabilities < ActiveRecord::Migration[8.0]
  SLUGS = %w[
    studio.scene_object.create
    studio.scene_object.transform
    studio.scene_object.duplicate
    studio.scene_object.destroy
  ].freeze

  def up
    load Rails.root.join(
      "db/seeds/studio_scene_object_capabilities.rb"
    )
  end

  def down
    NevaehCapability
      .where(
        slug: SLUGS
      )
      .delete_all
  end
end
