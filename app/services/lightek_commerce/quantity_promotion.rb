# frozen_string_literal: true

module LightekCommerce
  class QuantityPromotion
    def self.savings(rule, lines, qualifying_keys, reward_keys)
      units = lines.to_h { |key, quantity, price, _| [key, [quantity, price]] }
      qualifying_count = qualifying_keys.sum { |key| units.fetch(key).first }
      reward_count = reward_keys.sum { |key| units.fetch(key).first }
      distinct_count = (qualifying_keys | reward_keys).sum { |key| units.fetch(key).first }
      applications = [qualifying_count / rule.buy_quantity, reward_count / rule.get_quantity,
        distinct_count / (rule.buy_quantity + rule.get_quantity), rule.applications_per_order].compact.min
      return {} unless applications.positive?

      available = units.transform_values(&:first)
      # Reserve units that can only qualify first. If a line can qualify or be
      # rewarded, keep the cheaper units available for the reward.
      purchases_needed = applications * rule.buy_quantity
      shared_keys = qualifying_keys & reward_keys
      purchase_keys = (qualifying_keys - shared_keys) + shared_keys.sort_by { |key| [-units.fetch(key).last, key] }
      purchase_keys.each do |key|
        reserved = [purchases_needed, available.fetch(key)].min
        available[key] -= reserved
        purchases_needed -= reserved
        break if purchases_needed.zero?
      end

      rewards_needed = applications * rule.get_quantity
      reward_keys.sort_by { |key| [units.fetch(key).last, key] }.each_with_object({}) do |key, savings|
        rewarded = [rewards_needed, available.fetch(key)].min
        price = units.fetch(key).last
        unit_savings = rule.reward_type == 'fixed' ? [rule.amount, price].min : price * rule.amount / 100
        savings[key] = rewarded * unit_savings if rewarded.positive? && unit_savings.positive?
        rewards_needed -= rewarded
        break savings if rewards_needed.zero?
      end
    end
  end
end
