require_relative '../concerns/campaign_content_review'
# frozen_string_literal: true
module LightekMarketing
  class Campaign < ApplicationRecord
    include CampaignContentReview
    has_many :content_variants, class_name: 'LightekMarketing::ContentVariant'
    before_destroy do
      if defined?(LightekMarketing::ContentVariant) && LightekMarketing::ContentVariant.table_exists? && content_variants.exists?
        errors.add(:base, 'Content review history must be retained; complete the campaign instead')
        throw :abort
      end
    end
    self.table_name = "lightek_marketing_campaigns"
    has_many :growth_links, class_name: 'LightekGrowth::Link', dependent: :restrict_with_error
    belongs_to :site, class_name: "DymondSite::Site"
    validates :production_format, inclusion: {in: %w[portrait square landscape]}, if: -> { has_attribute?(:production_format) }
    CHANNELS = %w[landing_page email social].freeze
    STATUSES = %w[draft ready paused completed].freeze
    validates :name, presence: true, length: {maximum: 160}
    validates :channel, inclusion: {in: CHANNELS}
    validates :status, inclusion: {in: STATUSES}
    validates :cta_url, format: {with: /\Ahttps?:\/\//i}, allow_blank: true
    validates :media_url, length: {maximum: 1200}, format: {with: /\Ahttps:\/\//}, allow_blank: true
    validate :dates_in_order
    private
    def dates_in_order
      errors.add(:ends_at, "must follow the start time") if starts_at && ends_at && ends_at <= starts_at
    end
  end
end
