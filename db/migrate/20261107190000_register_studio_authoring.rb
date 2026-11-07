class RegisterStudioAuthoring < ActiveRecord::Migration[8.0]
  def up
    load Rails.root.join("db/seeds/lightek_studio_workspace_capabilities.rb")
  end
  def down
    NevaehCapability.where(slug:%w[studio.workspace.blender.authoring.edit studio.workspace.blender.authoring.preview]).delete_all
  end
end
