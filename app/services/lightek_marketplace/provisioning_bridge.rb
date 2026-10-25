# frozen_string_literal: true
module LightekMarketplace
  module ProvisioningBridge
    def fulfill(purchase)
      return super unless Delivery.managed?(purchase)
      receipt = Delivery.call(purchase)
      {ok: true, marketplace_delivery: receipt}
    rescue Delivery::NotReady => e
      purchase.mark_failed!(e.message)
      {ok: false, error: e.message}
    end
  end
end
