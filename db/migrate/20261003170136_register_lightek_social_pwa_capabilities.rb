# frozen_string_literal: true

class RegisterLightekSocialPwaCapabilities <
      ActiveRecord::Migration[8.0]

  SLUGS =
    %w[
      social.people.recommend
      social.relationship.context
      social.connection.opportunities
      social.follow
      social.friendship.request
      social.friendship.respond
      social.friendship.end
      social.block
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
