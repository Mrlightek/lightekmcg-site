module LightekAccounting
  class AuditEvent < ApplicationRecord
    self.table_name = 'lightek_accounting_audit_events'
    belongs_to :book
    belongs_to :actor, class_name: 'User'
    def self.record!(actor:,record:,action:)
      create!(book_id: record.is_a?(Book) ? record.id : record.book_id, actor: actor, action: action,
        record_type: record.class.name, record_id: record.id,
        proof_digest: record.respond_to?(:sealed_data) ? Digest::SHA256.hexdigest(JSON.generate(record.sealed_data)) : nil)
    end
  end
end
