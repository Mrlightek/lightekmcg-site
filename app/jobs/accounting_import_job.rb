class AccountingImportJob < ApplicationJob
  queue_as :default
  self.enqueue_after_transaction_commit = true if respond_to?(:enqueue_after_transaction_commit=)
  def perform(import_id,actor_id,accept_duplicates = false)
    record = LightekAccounting::Import.find(import_id)
    actor = User.find(actor_id)
    access = LightekAccounting::Access.new(actor: actor,employer: record.book.employer)
    LightekAccounting::Imports.commit!(access: access,record: record,accept_possible_duplicates: accept_duplicates)
  rescue StandardError => error
    record&.update!(status: 'failed',data: record.data.merge('error'=>error.is_a?(ArgumentError) ? error.message : "Import failed (#{error.class.name.demodulize})"))
  end
end
