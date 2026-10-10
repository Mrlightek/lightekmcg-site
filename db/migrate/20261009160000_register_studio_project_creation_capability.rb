# frozen_string_literal: true

class RegisterStudioProjectCreationCapability < ActiveRecord::Migration[8.0]
  def up
    load Rails.root.join("db/seeds/studio_project_creation_capability.rb")
  end

  def down
    NevaehCapability.where(slug: "studio.project.create").delete_all
  end
end
