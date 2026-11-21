# frozen_string_literal: true

module Studio
  module Broadcasting
    class OperatingPlan < ApplicationRecord
      self.table_name = "studio_broadcast_operating_plans"
      MONEY_FIELDS = %i[budget actual_cost actual_revenue].freeze

      belongs_to :site, class_name: "DymondSite::Site"
      belongs_to :department, class_name: "LightekPeople::Department"
      belongs_to :owner, class_name: "::User"
      belongs_to :channel, class_name: "Studio::Broadcasting::Channel", optional: true

      validates :month, presence: true
      validates :coverage, :targets, presence: true, length: { maximum: 4000 }
      validates :market, length: { maximum: 120 }
      validates :budget_cents, :actual_cost_cents, :actual_revenue_cents,
        numericality: { only_integer: true, in: 0..99_999_999_999 }
      validate do
        errors.add(:channel, "must belong to this operation") if channel && channel.site_id != site_id
        errors.add(:month, "must start on the first day") if month && month.day != 1
      end

      def margin_cents = actual_revenue_cents - actual_cost_cents
      def remaining_budget_cents = budget_cents - actual_cost_cents
    end
  end
end
