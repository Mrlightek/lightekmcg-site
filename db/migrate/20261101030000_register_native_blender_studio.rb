# frozen_string_literal: true
class RegisterNativeBlenderStudio < ActiveRecord::Migration[8.0]
  def up
    load Rails.root.join("db/seeds/lightek_studio_workspace_capabilities.rb")
  end
  def down
    NevaehCapability.where(slug:%w[studio.workspace.blender.template.use studio.workspace.blender.camera.create studio.workspace.blender.camera.save studio.workspace.blender.demo.import studio.workspace.blender.prepare]).delete_all
  end
end
