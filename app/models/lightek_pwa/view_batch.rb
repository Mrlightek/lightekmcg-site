module LightekPwa
  class ViewBatch < ApplicationRecord
    self.table_name = 'lightek_pwa_view_batches'
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :recorded_by, class_name: 'User'
    has_many :view_earnings, class_name: 'LightekPwa::ViewEarning', dependent: :restrict_with_error
    has_one_attached :report
    has_one_attached :finalized_receipt
    validates :channel_id, format: {with: /\AUC[A-Za-z0-9_-]{22}\z/}
    validates :finalized_cents, :creator_liability_cents, numericality: {only_integer: true, greater_than_or_equal_to: 0}
    validates :estimated_micros, numericality: {only_integer: true, greater_than: 0}
    validates :state, inclusion: {in: %w[reconciled funded funding_held]}
  end
end
