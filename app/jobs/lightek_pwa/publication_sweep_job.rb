module LightekPwa
  class PublicationSweepJob < ApplicationJob
    queue_as :default
    def perform
      PublicationOutbox.where('delivered_revision < revision').limit(500).pluck(:id).each do |id|
        PublicationSyncJob.perform_later(id)
      end
    end
  end
end
