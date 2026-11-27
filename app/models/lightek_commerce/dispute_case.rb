# frozen_string_literal: true

module LightekCommerce
  class DisputeCase < ApplicationRecord
    self.table_name = 'lightek_commerce_dispute_cases'
    belongs_to :order, class_name: 'LightekCommerce::Order'

    def self.record!(order:, dispute:, alert: true, historical: false)
      order.with_lock do
        reference = dispute.id.to_s
        return unless reference.match?(/\Adp_[A-Za-z0-9_]{1,150}\z/) &&
          order.paid_at? && dispute.currency == order.currency && dispute.amount.to_i.between?(1, order.cash_paid_cents)

        record = find_or_initialize_by(order: order, processor_reference: reference)
        return record if historical && record.persisted?

        due = dispute.evidence_details&.due_by.to_i
        merchant = order.site.tenant
        record.assign_attributes(status: dispute.status, reason: dispute.reason, amount_cents: dispute.amount,
          due_at: (Time.at(due) if due.positive?))
        if alert && record.alerted_at.nil? && MerchantDisputes::RESPONDABLE.include?(dispute.status) &&
            due > Time.current.to_i && merchant.is_a?(User)
          DymondDash::Notification.create!(recipient: merchant, subject: order, category: 'system',
            title: 'Store payment dispute needs a response',
            body: "Order ##{order.id} has a dispute with a response deadline of #{Time.at(due).utc.strftime('%Y-%m-%d %H:%M UTC')}.",
            url: "/dashboard/commerce/orders/#{order.id}/disputes?site_id=#{order.site_id}")
          record.alerted_at = Time.current
        end
        record.save!
      end
    end
  end
end
