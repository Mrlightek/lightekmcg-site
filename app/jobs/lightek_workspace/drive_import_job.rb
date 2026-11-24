module LightekWorkspace
  class DriveImportJob < ApplicationJob
    queue_as :default
    self.enqueue_after_transaction_commit = true

    def perform(id, token)
      run = DriveImport.find_by(id: id)
      DriveImportRunner.new(run, token).perform if run
    end
  end
end
