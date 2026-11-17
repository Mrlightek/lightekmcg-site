module LightekPwa
  class CreatorSettlementJob < ApplicationJob
    queue_as :default
    retry_on Stripe::StripeError, Net::ReadTimeout, wait: :polynomially_longer, attempts: 8
    def perform(id)
      earning = CreatorEarning.find_by(id: id)
      CreatorSettlement.refresh!(earning) if earning
    end
  end
end
