module LightekAgency
  class DemoSweepJob < ApplicationJob
    queue_as :default
    def perform
      Demo.where(cleaned_at: nil).where('expires_at <= ? OR converted_at IS NOT NULL', Time.current).find_each do |demo|
        DemoCleanupJob.perform_later(demo.id)
      end
      DemoRequest.where(status: 'pending').where('expires_at < ?', 7.days.ago).delete_all
    end
  end
end
