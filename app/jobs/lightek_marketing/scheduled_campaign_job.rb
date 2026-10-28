# frozen_string_literal: true
module LightekMarketing
  class ScheduledCampaignJob < ApplicationJob
    queue_as :default
    def perform(campaign_id)
      campaign = Campaign.find(campaign_id)
      return unless campaign.status == "ready" && campaign.channel == "email"
      return if campaign.starts_at && campaign.starts_at.future?
      return if campaign.ends_at && campaign.ends_at.past?
      AudienceDispatch.call!(campaign: campaign)
    end
  end
end
