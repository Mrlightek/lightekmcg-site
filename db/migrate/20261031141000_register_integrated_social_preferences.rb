class RegisterIntegratedSocialPreferences < ActiveRecord::Migration[8.0]
  def up
    load Rails.root.join("db/seeds/lightek_community_capabilities.rb")
  end
  def down
    NevaehCapability.where(slug: %w[community.profile.preferences community.top.people.save]).delete_all
  end
end
