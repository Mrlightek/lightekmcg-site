# frozen_string_literal: true
module LightekMarketing
  # Sends a reviewed campaign through the existing mail submission pipeline:
  # Lightek Mail enforces account ownership, recipient limits, abuse policies and delivery.
  class EmailDelivery
    class Invalid < StandardError; end

    def self.call!(campaign:, actor:)
      campaign.with_lock do
        raise Invalid, "Only ready email campaigns can be sent" unless campaign.channel == "email" && campaign.status == "ready"
        raise Invalid, "Campaign already sent" if campaign.sent_at? || campaign.mail_message_id.present?
        raise Invalid, "Campaign must include a headline and message" if campaign.headline.blank? || campaign.message.blank?
        raise Invalid, "Campaign is not scheduled yet" if campaign.starts_at && campaign.starts_at.future?
        raise Invalid, "Campaign has expired" if campaign.ends_at && campaign.ends_at.past?
        account = LightekMail::Account.where(user: actor).find_by(id: campaign.mail_account_id)
        raise Invalid, "Select a mailbox you own" unless account
        raise Invalid, "Mailbox is not ready" unless account.sending_ready?
        recipient = LightekMail::Submission.addresses(campaign.recipient_email).sole
        text = [campaign.message, (campaign.cta_url.present? ? "#{campaign.cta_label}: #{campaign.cta_url}" : nil)].compact.join("\n\n")
        message = LightekMail::Submission.create!(account: account,
          attributes: {"to" => recipient, "subject" => campaign.headline, "text" => text},
          idempotency_key: "marketing_campaign_#{campaign.id}_send")
        campaign.update!(mail_message_id: message.id, sent_at: Time.current, status: "completed")
        message
      end
    end
  end
end
