# frozen_string_literal: true

class RegisterStudioPwaBootstrapCapability < ActiveRecord::Migration[8.0]
  def up
    load(
      Rails.root.join(
        "db/seeds/studio_pwa_capabilities.rb"
      )
    )
  end

  def down
    NevaehCapability
      .where(
        slug: [
          "studio.pwa.bootstrap"
        ]
      )
      .delete_all
  end
end
