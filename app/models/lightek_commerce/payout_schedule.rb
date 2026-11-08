module LightekCommerce
  class PayoutSchedule < ApplicationRecord
    self.table_name = 'lightek_merchant_payout_schedules'
    belongs_to :merchant, class_name: 'User'
    validates :cadence, inclusion: {in: %w[biweekly weekly]}
    validates :next_run_at, presence: true
    def interval_days = cadence == 'weekly' ? 7 : 14
    def self.for!(merchant)
      create_or_find_by!(merchant: merchant) { |s| s.next_run_at = 14.days.from_now.beginning_of_day + 14.hours }
    end
  end
end
