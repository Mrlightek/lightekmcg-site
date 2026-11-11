class RegisterStudioCharacterPerformance < ActiveRecord::Migration[8.0]
  def up
    load Rails.root.join("db/seeds/lightek_studio_workspace_capabilities.rb")
  end
  def down
    NevaehCapability.where(slug:%w[studio.workspace.cast.create studio.workspace.cast.retry studio.workspace.cast.register studio.workspace.cast.place studio.workspace.performance.save studio.workspace.performance.remove studio.workspace.performance.preview]).delete_all
  end
end
