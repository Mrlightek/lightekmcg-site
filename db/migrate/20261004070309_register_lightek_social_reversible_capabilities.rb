# frozen_string_literal: true

class RegisterLightekSocialReversibleCapabilities <
      ActiveRecord::Migration[8.0]

  SLUGS =
    %w[
      social.unfollow
      social.blocks.list
      social.unblock
    ].freeze

  def up
    load Rails.root.join(
      "db/seeds/lightek_social_capabilities.rb"
    )
  end

  def down
    NevaehCapability
      .where(
        slug:
          SLUGS,

        handler:
          "LightekSocial::Workers::Pwa"
      )
      .delete_all
  end
end
