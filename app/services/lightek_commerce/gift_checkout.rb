# frozen_string_literal: true

require 'ostruct'

module LightekCommerce
  class GiftCheckout
    class Invalid < StandardError; end
    CARD_MINIMUM_CENTS = 50
    PROVIDER = 'stripe_gift_split'
    METADATA_FLAG = 'lightek_gift_redemption'

    def self.start!(order:, code:, address:)
      raise Invalid, 'Gift card redemption is unavailable.' unless GiftCards.platform_enabled?

      order.with_lock do
        return OpenStruct.new(url: nil) if order.gift_card_redemption? && order.paid_at?

        raise Invalid, 'This order cannot accept gift cards.' unless order.gift_card_redemption? && order.status == 'pending_payment'

        unless GiftRedemption.exists?(order: order)
          digest = GiftCard.digest(code)
          card = GiftCard.find_by(site: order.site, store_scope: order.gift_scope, livemode: live_mode?, code_digest: digest) if digest
          raise Invalid, 'This gift card is unavailable for this store.' unless card&.usable? && card.available_cents.positive?

          calculation = tax_quote!(order, address)
          hold!(order, card, calculation)
        end
      end
      begin_payment!(order)
    rescue ::Stripe::StripeError, LightekPayments::PayoutAccounts::Unavailable
      raise Invalid, 'Gift card checkout could not be confirmed. Check your orders before trying again.'
    end

    def self.hold!(order, card, calculation)
      baseline = order.subtotal_cents + order.buyer_fee_cents + order.shipping_cents
      tax = calculation.tax_amount_exclusive
      total = calculation.amount_total
      unless tax.is_a?(Integer) && tax >= 0 && total == baseline + tax && calculation.currency == order.currency &&
          calculation.id.to_s.match?(/\Ataxcalc_[A-Za-z0-9_]+\z/)
        raise Invalid, 'Stripe did not confirm the order tax.'
      end

      card.with_lock do
        unless card.site_id == order.site_id && card.usable? && card.available_cents.positive?
          raise Invalid, 'This gift card is unavailable for this store.'
        end

        applied = [total, card.available_cents].min
        applied = total - CARD_MINIMUM_CENTS if (total - applied).between?(1, CARD_MINIMUM_CENTS - 1)
        raise Invalid, 'The remaining charge is below the card minimum.' if applied <= 0

        card.update!(available_cents: card.available_cents - applied)
        GiftRedemption.create!(order: order, gift_card: card, amount_cents: applied, cash_cents: total - applied,
          tax_calculation: calculation.id)
        order.update!(gift_applied_cents: applied, tax_cents: tax, total_cents: total, payment_provider: PROVIDER)
      end
    end

    def self.begin_payment!(order)
      order.with_lock do
        redemption = GiftRedemption.find_by!(order: order)
        if order.status == 'pending_payment' && redemption.cash_cents.positive?
          redemption.update!(payment_attempted_at: Time.current) unless redemption.payment_attempted_at?
        end
      end

      order.with_lock do
        redemption = GiftRedemption.find_by!(order: order)
        return OpenStruct.new(url: nil) if order.paid_at?
        raise Invalid, 'This gift card checkout expired.' unless order.status == 'pending_payment' && redemption.state == 'held'
        return OpenStruct.new(url: nil) if redemption.cash_cents.zero?

        if order.payment_reference.blank?
          if redemption.payment_attempted_at < 22.hours.ago
            raise Invalid, 'The original card payment requires reconciliation.'
          end
          intent = ::Stripe::PaymentIntent.create({amount: redemption.cash_cents, currency: order.currency,
            payment_method_types: ['card'], metadata: metadata(order)}, options(order, 'gift-intent'))
          raise Invalid, 'Stripe did not confirm the card payment setup.' unless intent.id.to_s.match?(/\Api_[A-Za-z0-9_]+\z/) &&
            intent.amount == redemption.cash_cents && intent.currency == order.currency

          order.update!(payment_reference: intent.id)
        end
        OpenStruct.new(url: nil)
      end
    end

    def self.confirm!(order)
      order.with_lock do
        return order if order.paid_at?
        redemption = GiftRedemption.find_by!(order: order, state: 'held', cash_cents: 0)
        raise Invalid, 'This gift card checkout expired.' unless order.status == 'pending_payment'

        redemption.update!(payment_attempted_at: Time.current) unless redemption.payment_attempted_at?
      end
      order.with_lock do
        settle_locked!(order, GiftRedemption.find_by!(order: order)) unless order.paid_at?
      end
      order
    end

    def self.payment_summary(order)
      claim = GiftRedemption.find_by!(order: order, state: 'held')
      {gift_card_tender: true, cash_cents: claim.cash_cents, gift_cents: claim.amount_cents, total_cents: order.total_cents}
    end

    def self.session!(order)
      raise Invalid, 'This order is no longer awaiting payment.' unless order.status == 'pending_payment' && order.payment_reference.present?

      intent = ::Stripe::PaymentIntent.retrieve(order.payment_reference, options(order))
      validate_intent!(order, GiftRedemption.find_by!(order: order), intent)
      raise Invalid, 'This card payment is processing.' if %w[succeeded canceled processing].include?(intent.status)
      intent
    end

    def self.refresh!(order)
      return order unless order.status == 'pending_payment' && order.payment_reference.present?
      intent = ::Stripe::PaymentIntent.retrieve(order.payment_reference, options(order))
      settle_intent!(order, intent) if intent.status == 'succeeded'
      order.reload
    end

    def self.settle_intent!(order, intent)
      order.with_lock do
        redemption = GiftRedemption.find_by!(order: order)
        validate_intent!(order, redemption, intent)
        unless intent.status == 'succeeded' && intent.amount_received == redemption.cash_cents
          raise Invalid, 'The received card payment does not match the order.'
        end
        settle_locked!(order, redemption) unless order.paid_at?
      end
      order
    end

    def self.expire!(order)
      redemption = GiftRedemption.find_by(order: order)
      if order.payment_reference.blank? && redemption&.payment_attempted_at?
        redemption.cash_cents.zero? ? confirm!(order) : begin_payment!(order)
      end
      order.with_lock do
        return unless order.status == 'pending_payment'
        if order.payment_reference.present?
          intent = ::Stripe::PaymentIntent.retrieve(order.payment_reference, options(order))
          validate_intent!(order, GiftRedemption.find_by!(order: order), intent)
          return settle_intent!(order, intent) if intent.status == 'succeeded'
          intent = ::Stripe::PaymentIntent.cancel(intent.id, {}, options(order, 'gift-intent-cancel')) unless intent.status == 'canceled'
          raise Invalid, 'Stripe has not canceled the card payment.' unless intent.status == 'canceled'
        end
        OrderPlacement.cancel!(order)
      end
    end

    def self.process_event!(event)
      return if event.respond_to?(:account) && event.account.present?

      intent = event.data.object
      info = intent.metadata.to_h.stringify_keys
      order = Order.find_by(id: info['lightek_commerce_order_id'], payment_namespace: info['lightek_host_key'], payment_provider: PROVIDER)
      return unless order && info['lightek_site_id'] == order.site_id.to_s

      settle_intent!(order, intent)
    end

    def self.validate_intent!(order, redemption, intent)
      fields = intent.to_h.deep_stringify_keys
      unless fields['id'] == order.payment_reference && fields['currency'] == order.currency && fields['amount'] == redemption.cash_cents &&
          metadata(order).stringify_keys.all? { |key, value| fields.fetch('metadata', {})[key] == value }
        raise Invalid, 'The card payment does not match the gift card order.'
      end
    end

    def self.settle_locked!(order, redemption)
      raise Invalid, 'The gift card reservation is unavailable.' unless order.status == 'pending_payment' && redemption.state == 'held'
      reference = PaymentIdentity.key(order, 'gift-tax')
      tax = ::Stripe::Tax::Transaction.create_from_calculation({calculation: redemption.tax_calculation, reference: reference},
        options(order, 'gift-tax'))
      unless tax.id.to_s.start_with?('tax_') && tax.reference == reference && tax.currency == order.currency
        raise Invalid, 'Stripe has not confirmed the gift card order tax.'
      end

      redemption.update!(state: 'captured', tax_transaction: tax.id)
      order.update!(status: 'paid', paid_at: Time.current)
      if order.shipping_quote && order.shipping_quote.broker_reference.blank?
        order.shipping_quote.update!(purchase_order: order)
        LightekShipping::LabelJob.perform_later(order.id)
      end
      RevenueSharing.record!(order)
      OrderConfirmationJob.perform_later(order.id)
    end

    def self.tax_quote!(order, address)
      quote = order.shipping_quote
      physical = order.items.any? { |item| item.purchase_snapshot['product_type'] == 'physical' }
      raise Invalid, 'Select a shipping quote before using a gift card on physical goods.' if physical && !quote
      if quote
        delivery = quote.shipment_payload.fetch('recipients').sole.fetch('address')
        address = {'line1' => delivery.fetch('streetLines').first, 'postal_code' => delivery['postalCode'],
          'city' => delivery['city'], 'state' => delivery['stateOrProvinceCode'], 'country' => delivery['countryCode']}
      end
      details = address.to_h.stringify_keys.slice('line1', 'city', 'state', 'postal_code', 'country')
        .transform_values { |value| value.to_s.strip }
      details['country'] ||= 'US'
      unless details['country'] == 'US' && %w[line1 city state postal_code].all? { |field| details[field].present? && details[field].length <= 120 }
        raise Invalid, 'Enter a complete US billing address for your gift card payment.'
      end

      lines = if order.discount_amount.positive?
        Discounts.processor_items(order).map { |item| item.fetch(:price_data).fetch(:unit_amount) * item.fetch(:quantity) }
      else
        order.items.map(&:line_total_cents)
      end
      taxable = lines.select(&:positive?).each_with_index.map { |amount, index| {amount: amount, reference: "item-#{index}", tax_behavior: 'exclusive'} }
      if order.buyer_fee_cents.positive?
        taxable << {amount: order.buyer_fee_cents, reference: 'checkout-fee',
          tax_code: order.buyer_fee_breakdown.fetch('tax_code'), tax_behavior: 'exclusive'}
      end
      raise Invalid, 'This order has no payable merchandise.' if taxable.empty?

      input = {currency: order.currency, customer_details: {address: details, address_source: quote ? 'shipping' : 'billing'}, line_items: taxable}
      if order.shipping_cents.positive?
        input[:shipping_cost] = {amount: order.shipping_cents, tax_code: 'txcd_92010001', tax_behavior: 'exclusive'}
      end
      ::Stripe::Tax::Calculation.create(input, options(order))
    end

    def self.metadata(order) = PaymentIdentity.metadata(order).merge(METADATA_FLAG => '1')

    def self.live_mode?
      LightekPayments::PayoutAccounts.options[:api_key].match?(/\A(?:sk|rk)_live_/)
    end

    def self.options(order, action = nil)
      result = LightekPayments::PayoutAccounts.options
      result[:idempotency_key] = PaymentIdentity.key(order, action) if action
      result
    end

    private_class_method :hold!, :settle_locked!, :tax_quote!, :metadata
  end
end
