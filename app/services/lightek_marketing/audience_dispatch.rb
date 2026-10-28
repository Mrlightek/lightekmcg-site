# frozen_string_literal: true
module LightekMarketing
  class AudienceDispatch
    def self.call!(campaign:)
      campaign.with_lock do
        raise ArgumentError, "Campaign must be reviewed and ready" unless campaign.channel == "email" && campaign.status == "ready"
        raise ArgumentError, "Campaign not in its sending window" if (campaign.starts_at && campaign.starts_at.future?) || (campaign.ends_at && campaign.ends_at.past?)
        account = LightekMail::Account.find_by(id: campaign.mail_account_id)
        raise ArgumentError, "Owned sender mailbox required" unless account && account.user_id == campaign.site.tenant_id && account.sending_ready?
        contacts = Contact.subscribed.where(site_id: campaign.site_id).order(:id)
        raise ArgumentError, "No subscribed contacts" unless contacts.exists?
        contacts.find_each do |contact|
          delivery = Delivery.find_or_create_by!(campaign: campaign, contact: contact)
          CampaignDeliveryJob.perform_later(delivery.id) if delivery.status == "pending"
        end
      end
    end
  end
end
