module LightekMarketing
  class PublicationSlot < ApplicationRecord
    self.table_name = 'lightek_marketing_publication_slots'
    STATES = %w[scheduled dispatching submitted published blocked needs_review canceled].freeze
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :campaign, class_name: 'LightekMarketing::Campaign'
    belongs_to :connection, class_name: 'LightekMarketing::SocialConnection'
    belongs_to :scheduled_by, class_name: 'User'
    belongs_to :social_post, class_name: 'LightekMarketing::SocialPost', optional: true
    validates :status, inclusion: {in: STATES}
    validates :scheduled_at, :request_key, :content_digest, presence: true
    validates :error_message, length: {maximum: 1000}
    validate do
      errors.add(:base, 'Campaign and destination must belong to this website') if (campaign && campaign.site_id != site_id) || (connection && connection.site_id != site_id)
      if persisted? && (changes.keys & %w[site_id campaign_id connection_id scheduled_by_id request_key content_digest scheduled_at time_zone]).any?
        errors.add(:base, 'Cancel and create a new slot to change its reviewed inputs')
      end
    end
  end
end
