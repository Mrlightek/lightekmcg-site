# frozen_string_literal: true
require 'digest'

module LightekCommerce
  class MerchantDisputes
    class Unavailable < StandardError; end
    RESPONDABLE = %w[needs_response warning_needs_response].freeze

    def initialize(order:, actor:)
      @order = order
      raise ActiveRecord::RecordNotFound unless order.site.tenant == actor &&
        LightekSettings::WebsiteIdentity.sites_for(actor).exists?(id: order.site_id)

      @options = LightekPayments::PayoutAccounts.options
      @intent = MerchantLedger.dispute_payment_intent!(order, @options)
    rescue LightekPayments::PayoutAccounts::Unavailable, MerchantLedger::Invalid, ::Stripe::StripeError
      raise Unavailable, 'This order’s provider payment could not be verified.'
    end

    def list
      ::Stripe::Dispute.list({payment_intent: @intent, limit: 25}, @options).data.select { |row| belongs_to_order?(row) }
    rescue ::Stripe::StripeError
      raise Unavailable, 'The order’s disputes are temporarily unavailable.'
    end

    def respond!(id:, evidence:, confirmed:)
      raise ActiveRecord::RecordNotFound unless id.to_s.match?(/\Adp_[a-zA-Z0-9_]{1,150}\z/)
      message = evidence.to_s.strip
      unless confirmed && message.present? && message.length <= 20_000
        raise Unavailable, 'Enter and confirm the evidence before submitting.'
      end

      @order.with_lock do
        dispute = ::Stripe::Dispute.retrieve(id, @options)
        raise ActiveRecord::RecordNotFound unless dispute.id == id && belongs_to_order?(dispute)
        unless RESPONDABLE.include?(dispute.status) && dispute.evidence_details&.due_by.to_i > Time.current.to_i &&
            dispute.evidence_details&.submission_count.to_i.zero?
          raise Unavailable, 'This dispute is no longer open for a response.'
        end

        digest = Digest::SHA256.hexdigest(message).first(32)
        ::Stripe::Dispute.update(id, {evidence: {uncategorized_text: message}, submit: true},
          @options.merge(idempotency_key: PaymentIdentity.key(@order, "dispute-#{id}-response-#{digest}")))
      end
    rescue ::Stripe::StripeError
      raise Unavailable, 'The response could not be confirmed. Refresh the dispute before retrying.'
    end

    private

    def belongs_to_order?(dispute)
      intent = dispute.payment_intent
      intent = intent.id if intent.respond_to?(:id)
      intent == @intent && dispute.currency == @order.currency && dispute.amount.to_i.between?(1, @order.total_cents)
    end
  end
end
