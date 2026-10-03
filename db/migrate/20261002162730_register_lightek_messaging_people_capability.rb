# frozen_string_literal: true

class RegisterLightekMessagingPeopleCapability <
      ActiveRecord::Migration[8.0]

  def up
    load Rails.root.join(
      "db/seeds/lightek_messaging_capabilities.rb"
    )
  end

  def down
    NevaehCapability
      .where(
        slug:
          "messages.people",
        handler:
          "LightekMessaging::Workers::Pwa"
      )
      .delete_all
  end
end
