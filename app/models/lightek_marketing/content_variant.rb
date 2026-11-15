module LightekMarketing
  class ContentVariant < ApplicationRecord
    self.table_name = 'lightek_marketing_content_variants'
    COPY_FIELDS = %w[headline message cta_label cta_url media_url].freeze
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :campaign, class_name: 'LightekMarketing::Campaign'
    belongs_to :created_by, class_name: 'User'
    belongs_to :approved_by, class_name: 'User', optional: true
    validates :status, inclusion: {in: %w[draft approved]}
    validates :headline, presence: true, length: {maximum: 200}
    validates :message, presence: true, length: {maximum: 8000}
    validates :cta_label, presence: true, length: {maximum: 60}
    validates :cta_url, length: {maximum: 400}, format: {with: /\Ahttps:\/\/[^\s]+\z/}
    validates :media_url, length: {maximum: 1200}, format: {with: /\Ahttps:\/\/[^\s]+\z/}, allow_blank: true
    validates :batch_key, :baseline_digest, :angle, presence: true
    validate do
      errors.add(:campaign, 'must belong to this website') if campaign && campaign.site_id != site_id
      errors.add(:source_snapshot, 'must be a bounded object') unless source_snapshot.is_a?(Hash) && source_snapshot.to_json.bytesize <= 64_000
      errors.add(:base, 'Approved copy is immutable; generate another draft') if persisted? && status_was == 'approved' && changed?
      if persisted? && (changes.keys & %w[site_id campaign_id created_by_id batch_key angle baseline_digest source_snapshot]).any?
        errors.add(:base, 'Source evidence is immutable')
      end
    end
  end
end
