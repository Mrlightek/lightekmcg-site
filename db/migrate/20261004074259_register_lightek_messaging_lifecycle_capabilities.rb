# frozen_string_literal: true

class RegisterLightekMessagingLifecycleCapabilities <
      ActiveRecord::Migration[8.0]

  SLUGS =
    %w[
      messages.delete
      messages.leave
    ].freeze

  def up
    load Rails.root.join(
      "db/seeds/lightek_messaging_capabilities.rb"
    )
  end

  def down
    NevaehCapability
      .where(
        slug:
          SLUGS,

        handler:
          "LightekMessaging::Workers::Pwa"
      )
      .delete_all
  end
end
