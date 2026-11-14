class RegisterStudioSpeechAnalysis < ActiveRecord::Migration[8.0]
  def up
    load Rails.root.join("db/seeds/lightek_studio_workspace_capabilities.rb")
  end
  def down
    NevaehCapability.where(slug:%w[studio.workspace.performance.analyze studio.workspace.performance.analysis]).delete_all
  end
end
