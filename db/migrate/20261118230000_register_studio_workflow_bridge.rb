class RegisterStudioWorkflowBridge < ActiveRecord::Migration[8.0]
  def up
    load Rails.root.join("db/seeds/lightek_studio_workspace_capabilities.rb")
  end
  def down
    NevaehCapability.where(slug:%w[studio.workspace.workflow.create studio.workspace.workflow.status studio.workspace.workflow.plan studio.workspace.workflow.save studio.workspace.workflow.quote]).delete_all
  end
end
