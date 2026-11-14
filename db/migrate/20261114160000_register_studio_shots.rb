class RegisterStudioShots < ActiveRecord::Migration[8.0]
  def up
    load Rails.root.join("db/seeds/lightek_studio_workspace_capabilities.rb")
  end

  def down
    NevaehCapability.where(slug: %w[studio.workspace.shots.save studio.workspace.shots.list]).delete_all
  end
end
