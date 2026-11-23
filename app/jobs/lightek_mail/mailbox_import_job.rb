module LightekMail
  class MailboxImportJob < ApplicationJob
    queue_as :default
    self.enqueue_after_transaction_commit = true

    def perform(id, token)
      import = MailboxImport.find_by(id: id)
      MailboxImportRunner.new(import, token).run if import
    end
  end
end
