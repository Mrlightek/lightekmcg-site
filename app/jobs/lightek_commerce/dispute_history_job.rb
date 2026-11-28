# frozen_string_literal: true

module LightekCommerce
  class DisputeHistoryJob < ApplicationJob
    retry_on ::Stripe::StripeError, wait: :polynomially_longer, attempts: 4
    retry_on LightekPayments::PayoutAccounts::Unavailable, wait: :polynomially_longer, attempts: 4

    def perform(site_id, merchant_id, after_id = 0)
      merchant = User.find_by(id: merchant_id)
      return unless merchant

      site = LightekSettings::WebsiteIdentity.sites_for(merchant).find_by(id: site_id, tenant: merchant)
      return unless site

      orders = Order.visible.where(site: site, payment_provider: %w[stripe stripe_invoice stripe_gift_split])
        .where.not(paid_at: nil).where('id > ?', after_id).order(:id).limit(101).to_a
      orders.first(100).each do |order|
        MerchantDisputes.new(order: order, actor: merchant).each_dispute do |dispute|
          DisputeCase.record!(order: order, dispute: dispute, alert: false, historical: true)
        end
      rescue MerchantDisputes::Unverified
        next
      end
      self.class.perform_later(site_id, merchant_id, orders[99].id) if orders.size > 100
    end
  end
end
