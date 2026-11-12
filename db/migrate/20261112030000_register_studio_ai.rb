class RegisterStudioAi < ActiveRecord::Migration[8.0]
  def up
    load Rails.root.join("db/seeds/lightek_studio_workspace_capabilities.rb")
  end
  def down
    NevaehCapability.where(slug:%w[studio.workspace.ai.status studio.workspace.ai.generate studio.workspace.ai.jobs]).delete_all
  end
end
