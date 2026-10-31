# frozen_string_literal: true
class RegisterStudioMediaCapabilities < ActiveRecord::Migration[8.0]
  def up
    load Rails.root.join("db/seeds/lightek_studio_workspace_capabilities.rb")
  end

  def down
    NevaehCapability.where(slug: %w[studio.workspace.asset.import studio.workspace.assets.list studio.workspace.asset.place studio.workspace.timeline.save studio.workspace.timeline.quote]).delete_all
  end
end
