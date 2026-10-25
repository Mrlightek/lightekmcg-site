# frozen_string_literal: true
module LightekMarketplace
  module BankAdapter
    module_function
    # Releases of Bank may name a fixed period monthly or monthly_only. Ask the
    # actual model which spelling produces exactly the requested interval.
    def billing_period(billing, plan)
      return "customer_choice" if billing == "both"
      return "customer_choice" unless %w[monthly annual].include?(billing)
      candidates = [billing, "#{billing}_only"]
      candidates.find do |candidate|
        probe = DymondBank::Offer.new(billing_period: candidate, subscription_plan: plan)
        probe.valid?
        probe.errors[:billing_period].empty? && Array(probe.available_intervals).map(&:to_s) == [billing]
      end || raise(ArgumentError, "Bank does not support a fixed #{billing} billing period")
    end
  end
end
