module LightekMail
  class DiscoveryEvent < ApplicationRecord
    self.table_name = "lightek_mail_discovery_events"

    belongs_to :employer, class_name: "User"
    belongs_to :drive, class_name: "LightekWorkspace::Drive", optional: true
    belongs_to :actor, class_name: "User", optional: true
    belongs_to :matter, class_name: "LightekMail::Matter", optional: true
    belongs_to :account, class_name: "LightekMail::Account", optional: true
  end
end
