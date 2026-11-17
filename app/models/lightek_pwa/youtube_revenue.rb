module LightekPwa
  # Imported YouTube estimates are accounting evidence, never a cash balance.
  class YoutubeRevenue < ApplicationRecord
    self.table_name = 'lightek_pwa_youtube_revenues'
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :user
    belongs_to :recorded_by, class_name: 'User'
    has_one_attached :report
    validates :video_id, format: {with: Youtube::ID}
    validates :views, numericality: {only_integer: true, greater_than_or_equal_to: 0}
    validates :amount_cents, numericality: {only_integer: true, greater_than_or_equal_to: 0}
    validates :creator_share_bps, numericality: {only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 10_000}
    validates :source_reference, :report_sha256, :period_start, :period_end, presence: true
    validates :currency, inclusion: {in: %w[usd]}
    validate { errors.add(:period_end, 'must follow period start') if period_start && period_end && period_end < period_start }
    def creator_cents = amount_cents * creator_share_bps / 10_000
    def earnings_per_thousand_views_cents = views.positive? ? creator_cents * 1000.0 / views : nil
    def platform_cents = amount_cents - creator_cents
  end
end
