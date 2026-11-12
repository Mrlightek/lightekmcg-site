module LightekConnect
  class Event < ApplicationRecord
    self.table_name = "lightek_connect_events"
    belongs_to :connection, optional: true
    def self.record!(connection, action, resource: nil, details: {})
      create!(connection: connection, action: action, resource: resource, details: details)
    end
  end
end
