module LightekPwa
  class CreatorEarning < ApplicationRecord
    self.table_name = 'lightek_pwa_creator_earnings'
    after_create_commit :refresh_payment_source
    def refresh_payment_source
      LightekPwa::CreatorSettlementJob.perform_later(id) if defined?(LightekPwa::CreatorSettlementJob)
    rescue StandardError => error
      Rails.logger.error("[Creator settlement] earning=#{id} enqueue=#{error.class}")
    end
    belongs_to :creator_payment, class_name: 'LightekPwa::CreatorPayment'
    belongs_to :order, class_name: 'LightekCommerce::Order'
    validates :state, inclusion: {in: %w[held available transfer_pending transferred reversed]}
    validates :principal_cents, numericality: {only_integer: true, greater_than: 0}
  end
end
