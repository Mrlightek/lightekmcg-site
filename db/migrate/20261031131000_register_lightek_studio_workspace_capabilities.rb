# frozen_string_literal: true
class RegisterLightekStudioWorkspaceCapabilities < ActiveRecord::Migration[8.0]
  def up
    load Rails.root.join("db/seeds/lightek_studio_workspace_capabilities.rb")
  end
  def down
    NevaehCapability.where(slug: "studio.render.preview", handler: "Studio::Workers::Preview").delete_all
    NevaehCapability.where(handler: "Studio::Workers::Workspace").delete_all
  end
end
