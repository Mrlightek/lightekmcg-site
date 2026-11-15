module LightekMarketing
  class MediaBinding < ApplicationRecord
    self.table_name = 'lightek_marketing_media_bindings'
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :campaign, class_name: 'LightekMarketing::Campaign'
    belongs_to :artifact, optional: true
    belongs_to :created_by, class_name: 'User'
    has_one_attached :file
    before_validation(on: :create) { self.token ||= SecureRandom.hex(24) }
    validates :token, :filename, :delivery_host, presence: true
    validate do
      errors.add(:campaign, 'must belong to this website') if campaign && campaign.site_id != site_id
      errors.add(:base, 'Published media identity is immutable') if persisted? && (changes.keys - %w[revoked_at updated_at]).any?
    end
    def public_url = Rails.application.routes.url_helpers.campaign_media_url(token: token, filename: filename, host: delivery_host, protocol: 'https')
    def usable?
      !revoked_at && file.attached? && file.blob.id == source_snapshot['blob_id'] && file.blob.checksum == source_snapshot['checksum']
    end
  end
end
