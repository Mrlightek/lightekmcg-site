class RegisterStudioCpuRenderResume < ActiveRecord::Migration[8.0]
  def up
    load Rails.root.join("db/seeds/lightek_studio_workspace_capabilities.rb")
  end
  def down
    NevaehCapability.where(slug:"studio.workspace.render.resume").delete_all
  end
end
