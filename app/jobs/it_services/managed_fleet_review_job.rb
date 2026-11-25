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
      open_ids = results.flat_map { |result| result.fetch(:opened) + result.fetch(:updated) }
      ItManagedDeviceIncident.open_incidents.where(id: open_ids, owner_id: owner.id).find_each do |incident|
        IncidentEscalation.call!(incident: incident)
      end
      results
    end
  end
end
