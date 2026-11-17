module LightekPwa
  class ViewEarning < ApplicationRecord
    self.table_name = 'lightek_pwa_view_earnings'
    belongs_to :view_batch, class_name: 'LightekPwa::ViewBatch'
    belongs_to :user
    before_validation { self.transfer_key ||= SecureRandom.uuid }
    validates :amount_cents, :views, numericality: {only_integer: true, greater_than_or_equal_to: 0}
    validates :state, inclusion: {in: %w[awaiting_funding available transfer_pending transferred held]}
    def earnings_per_thousand_views_cents = views.positive? ? amount_cents * 1000.0 / views : nil
  end
end
