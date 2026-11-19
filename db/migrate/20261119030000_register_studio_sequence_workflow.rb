class RegisterStudioSequenceWorkflow < ActiveRecord::Migration[8.0]
  def up
    load Rails.root.join("db/seeds/lightek_studio_workspace_capabilities.rb")
  end
  def down
    NevaehCapability.where(slug:%w[studio.workspace.sequence.catalog studio.workspace.sequence.prepare studio.workspace.sequence.status studio.workspace.sequence.retry studio.workspace.sequence.quote]).delete_all
  end
end
