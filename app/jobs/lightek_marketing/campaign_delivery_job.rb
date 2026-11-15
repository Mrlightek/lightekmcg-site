# frozen_string_literal: true
module LightekMarketing
  class CampaignDeliveryJob < ApplicationJob
    queue_as :default
    def perform(delivery_id)
      delivery = Delivery.includes(:contact, :campaign).find(delivery_id)
      campaign = delivery.campaign
      contact = delivery.contact
      campaign.with_lock do
        return unless delivery.status == "pending" && contact.subscribed_at? && !contact.unsubscribed_at?
        if campaign.has_attribute?(:content_review_required) && campaign.content_review_required? && (!campaign.content_approved? || delivery.content_digest != campaign.content_digest)
          Rails.logger.warn({event: 'lightek.growth.delivery_content_changed', campaign_id: campaign.id, delivery_id: delivery.id, site_id: campaign.site_id}.to_json)
          delivery.update!(status: 'failed', error_message: 'Approved campaign content changed before delivery. Review the campaign; do not silently resend new copy.')
          return
        end
        return unless campaign.status == "ready" && campaign.channel == "email"
        account = LightekMail::Account.find(campaign.mail_account_id)
        return unless account.sending_ready? && account.user_id == campaign.site.tenant_id
        unsubscribe_url = Rails.application.routes.url_helpers.unsubscribe_marketing_subscription_url(
          token: contact.signed_id(purpose: :marketing_unsubscribe),
          host: ENV.fetch("LIGHTEK_PUBLIC_HOST", "lightekmcg.com"), protocol: "https")
        message = LightekMail::Submission.create!(account: account,
          attributes: {"to" => contact.email, "subject" => campaign.headline,
            "text" => [campaign.message, campaign.cta_url, "Unsubscribe: #{unsubscribe_url}"].compact.join("\n\n")},
          idempotency_key: "campaign_#{campaign.id}_contact_#{contact.id}")
        delivery.update!(status: "queued", mail_message: message)
      end
    rescue LightekMail::Submission::Unavailable, ArgumentError => e
      delivery&.update!(status: "failed", error_message: e.message.truncate(1000))
      raise
    end
  end
end
