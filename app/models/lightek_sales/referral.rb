# frozen_string_literal: true

module LightekSales
  class Referral < ApplicationRecord
    self.table_name = 'lightek_sales_referrals'

    has_one :commission_payout, dependent: :restrict_with_error
    belongs_to :partner
    belongs_to :lead
    belongs_to :order, class_name: 'LightekCommerce::Order', optional: true
    belongs_to :recorded_by, class_name: 'User', optional: true

    validates :payout_reference, format: {with: /\A[a-zA-Z0-9_.:-]{3,160}\z/}, uniqueness: true, allow_nil: true
    validate do
      errors.add(:lead, 'must belong to the partner website') if lead && partner && lead.site_id != partner.site_id
    end

    def first_paid_order
      return order if order_id?
      return unless lead.opportunity_id?

      orders = LightekCommerce::Order.where(site_id: lead.site_id).where.not(paid_at: nil)
      quote_orders = Quote.where(site_id: lead.site_id, opportunity_id: lead.opportunity_id,
        status: 'accepted').select(:order_id)
      orders.where(id: quote_orders).order(:paid_at, :id).first
    end

    def payout_status(candidate)
      return 'Awaiting payment' unless candidate

      refund_review = candidate.refunded_cents.to_i.positive? ||
        candidate.status.in?(%w[refunded partially_refunded]) || candidate.refunds.where(status: 'pending').exists?
      return refund_review ? 'Paid · refund review' : 'Paid' if paid_at?
      return 'Refund review' if refund_review
      unless candidate.customer_email.casecmp?(lead.email) &&
          candidate.items.pluck(:product_id, :quantity) == [[partner.product_id, 1]]
        return 'Order does not match agreement'
      end
      return 'Awaiting fulfillment' unless candidate.status == 'fulfilled'
      return 'Awaiting merchant proceeds' if candidate.merchant_transfer_ref.blank?
      return 'Insufficient merchant proceeds' if candidate.merchant_transfer_amount_cents.to_i < commission_cents

      earlier_purchase = LightekCommerce::Order.where(site_id: lead.site_id)
        .where('LOWER(customer_email) = ?', candidate.customer_email.downcase)
        .where('paid_at < :paid_at OR (paid_at = :paid_at AND id < :id)', paid_at: candidate.paid_at, id: candidate.id)
      return 'Existing customer · review' if earlier_purchase.exists?

      'Ready to record'
    end

    def record_payout!(actor:, reference:, expected_order_id:)
      with_lock do
        reference = reference.to_s.strip
        if paid_at?
          return if payout_reference == reference && order_id.to_s == expected_order_id.to_s

          raise ArgumentError, 'This commission already has a payout receipt.'
        end

        if CommissionPayout.exists?(referral_id: id)
          raise ArgumentError, 'A Dymond Bank payout is already tracked for this commission.'
        end

        candidate = first_paid_order
        unless candidate && candidate.id.to_s == expected_order_id.to_s
          raise ArgumentError, 'The associated order changed. Review the commission again.'
        end

        candidate.with_lock do
          raise ArgumentError, 'The order is not eligible for commission payment.' unless payout_status(candidate) == 'Ready to record'

          update!(order: candidate, recorded_by: actor, payout_reference: reference, paid_at: Time.current)
        end
      end
    end
  end
end
