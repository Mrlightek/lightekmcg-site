module LightekPeople
  class AuditEvent < ApplicationRecord
    self.table_name = 'lightek_people_audit_events'
    belongs_to :employer, class_name: 'User'
    belongs_to :actor, class_name: 'User'
    def self.record!(employer:, actor:, action:, record:)
      create!(employer: employer, actor: actor, action: action, record_type: record.class.name, record_id: record.id)
    end
  end
end
