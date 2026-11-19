class RegisterValidatedPickupAction < ActiveRecord::Migration[8.0]
  def up
    load Rails.root.join("db/seeds/lightek_studio_workspace_capabilities.rb")
  end
  def down; end
end
