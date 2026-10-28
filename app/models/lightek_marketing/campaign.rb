# frozen_string_literal: true
module LightekMarketing
  class Campaign < ApplicationRecord
    self.table_name = "lightek_marketing_campaigns"
    belongs_to :site, class_name: "DymondSite::Site"
    CHANNELS = %w[landing_page email social].freeze
    STATUSES = %w[draft ready paused completed].freeze
    validates :name, presence: true, length: {maximum: 160}
    validates :channel, inclusion: {in: CHANNELS}
    validates :status, inclusion: {in: STATUSES}
    validates :cta_url, format: {with: /\Ahttps?:\/\//i}, allow_blank: true
    validate :dates_in_order
    private
    def dates_in_order
      errors.add(:ends_at, "must follow the start time") if starts_at && ends_at && ends_at <= starts_at
    end
  end
end
