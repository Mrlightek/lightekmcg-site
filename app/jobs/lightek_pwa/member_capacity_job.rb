module LightekPwa
  class MemberCapacityJob < ApplicationJob
    queue_as :default
    def perform
      SharedPool.where(status: 'ready').find_each(batch_size: 100) do |pool|
        begin
          CapacityAlerts.call!(pool)
        rescue StandardError => error
          Rails.logger.error("[PWA] Capacity notification failed pool=#{pool.id}: #{error.class}")
        end
      end
    end
  end
end
