class RegisterBlenderAuthoring < ActiveRecord::Migration[8.0]
  def up
    load Rails.root.join("db/seeds/lightek_studio_workspace_capabilities.rb")
  end
  def down
    NevaehCapability.where(slug:%w[studio.workspace.blender.object.save studio.workspace.blender.preview studio.workspace.blender.runtime.status studio.workspace.blender.library.install]).delete_all
  end
end
