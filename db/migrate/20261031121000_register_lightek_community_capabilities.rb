# frozen_string_literal: true
class RegisterLightekCommunityCapabilities < ActiveRecord::Migration[8.0]
  def up
    load Rails.root.join("db/seeds/lightek_community_capabilities.rb")
  end
  def down
    NevaehCapability.where(handler: "LightekCommunity::Workers::Pwa").delete_all
  end
end
