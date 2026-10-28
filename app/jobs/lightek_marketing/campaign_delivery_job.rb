# frozen_string_literal: true
module LightekMarketing
  class CampaignDeliveryJob < ApplicationJob
    queue_as :default
    def perform(delivery_id)
      delivery = Delivery.includes(:contact, :campaign).find(delivery_id)
      campaign = delivery.campaign
      contact = delivery.contact
      return unless delivery.status == "pending" && contact.subscribed_at? && !contact.unsubscribed_at?
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
    rescue LightekMail::Submission::Unavailable, ArgumentError => e
      delivery&.update!(status: "failed", error_message: e.message.truncate(1000))
      raise
    end
  end
end
