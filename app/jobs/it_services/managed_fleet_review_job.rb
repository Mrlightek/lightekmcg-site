# frozen_string_literal: true

module ItServices
  # Explicitly queued, bounded review. Scheduling/managed-service entitlement
  # must be configured by the caller; this job never scans all tenants.
  class ManagedFleetReviewJob < ApplicationJob
    queue_as :default

    def perform(owner_id:, limit: 250)
      owner = User.find_by(id: owner_id)
      return unless owner && LightekPeople::LifecycleAccess.active?(owner)
      results = ManagedFleetIncidents.review_owner!(owner: owner, limit: limit)
      results.flat_map { |result| result.fetch(:opened) }.each do |incident_id|
        IncidentEscalation.call!(incident: ItManagedDeviceIncident.find(incident_id))
      end
      results
    end
  end
end
