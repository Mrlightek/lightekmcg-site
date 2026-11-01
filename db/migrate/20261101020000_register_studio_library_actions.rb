# frozen_string_literal: true
class RegisterStudioLibraryActions < ActiveRecord::Migration[8.0]
  def up
    load Rails.root.join("db/seeds/lightek_studio_workspace_capabilities.rb")
  end
  def down
    NevaehCapability.where(slug: %w[studio.workspace.library.apply studio.workspace.asset.use studio.workspace.asset.publish studio.workspace.asset.retry]).delete_all
  end
end
