module LightekPwa
  class AdminEvent < ApplicationRecord
    self.table_name = "lightek_pwa_admin_events"
    belongs_to :site, class_name: "DymondSite::Site"
    belongs_to :actor, class_name: "User"
    validates :action, presence: true
  end
end
