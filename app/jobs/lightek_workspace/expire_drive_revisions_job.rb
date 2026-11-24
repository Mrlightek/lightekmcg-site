module LightekWorkspace
  class ExpireDriveRevisionsJob < ApplicationJob
    queue_as :default

    def perform
      DriveRetention.expire!
    end
  end
end
