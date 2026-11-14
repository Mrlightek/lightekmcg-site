class RegisterStudioAppearance < ActiveRecord::Migration[8.0]
  def up
    load Rails.root.join("db/seeds/lightek_studio_workspace_capabilities.rb")
  end
  def down
    NevaehCapability.where(slug:%w[studio.workspace.look.status studio.workspace.look.save studio.workspace.material.save]).delete_all
  end
end
