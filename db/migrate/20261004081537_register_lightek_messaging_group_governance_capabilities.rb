# frozen_string_literal: true

class RegisterLightekMessagingGroupGovernanceCapabilities <
      ActiveRecord::Migration[8.0]

  SLUGS =
    %w[
      messages.group.add_members
      messages.group.remove_member
      messages.group.promote_admin
      messages.group.demote_admin
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
