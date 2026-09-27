module LightekVault
  class AuditEvent < ApplicationRecord
    self.table_name = "lightek_vault_audit_events"
    belongs_to :secret, class_name: "LightekVault::Secret"
    validates :action, presence: true
  end
end
