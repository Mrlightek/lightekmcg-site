class RegisterStudioAiSetup < ActiveRecord::Migration[8.0]
  def up
    load Rails.root.join("db/seeds/lightek_studio_workspace_capabilities.rb")
  end
  def down
    NevaehCapability.where(slug:%w[studio.workspace.ai.setup.status studio.workspace.ai.setup.install]).delete_all
  end
end
