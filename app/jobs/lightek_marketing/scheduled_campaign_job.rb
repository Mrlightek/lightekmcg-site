# frozen_string_literal: true
module LightekMarketing
  class ScheduledCampaignJob < ApplicationJob
    queue_as :default
    def perform(campaign_id, expected_digest = nil)
      campaign = Campaign.find(campaign_id)
      if campaign.has_attribute?(:content_review_required) && campaign.content_review_required?
        unless campaign.content_approved? && campaign.content_digest == expected_digest
          Rails.logger.warn({event: 'lightek.growth.schedule_content_changed', campaign_id: campaign.id, site_id: campaign.site_id}.to_json)
          return
        end
      end
      return unless campaign.status == "ready" && campaign.channel == "email"
      return if campaign.starts_at && campaign.starts_at.future?
      return if campaign.ends_at && campaign.ends_at.past?
      AudienceDispatch.call!(campaign: campaign, expected_digest: expected_digest)
    end
  end
end
