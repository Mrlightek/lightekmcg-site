class RegisterCharacterSceneWorkflow < ActiveRecord::Migration[8.0]
  def up
    load Rails.root.join("db/seeds/lightek_studio_workspace_capabilities.rb")
  end
  def down
    NevaehCapability.where(slug:%w[studio.workspace.character.scene.prepare studio.workspace.character.scene.status studio.workspace.character.scene.retry studio.workspace.character.scene.quote]).delete_all
  end
end
