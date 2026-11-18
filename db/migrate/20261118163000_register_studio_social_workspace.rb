# frozen_string_literal: true

class RegisterStudioSocialWorkspace < ActiveRecord::Migration[8.0]
  def up
    load Rails.root.join("db/seeds/lightek_studio_workspace_capabilities.rb")
  end
end
