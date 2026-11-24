# frozen_string_literal: true

module ItServices
  # Scheduled entry point: explicitly opted-in, enrolled, owner-backed devices
  # only. This is observational monitoring, not a paid-service entitlement.
  class ManagedFleetScheduleJob < ApplicationJob
    queue_as :default

    def perform
      NetworkManagedDevice.where(managed_monitoring_enabled: true)
        .where.not(owner_id: nil).where.not(enrolled_at: nil)
        .select(:owner_id).distinct.pluck(:owner_id).each do |owner_id|
          owner = User.find_by(id: owner_id)
          next unless owner && LightekPeople::LifecycleAccess.active?(owner)
          ItServices::ManagedFleetReviewJob.perform_later(owner_id: owner_id)
        end
    end
  end
end
