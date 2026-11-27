# frozen_string_literal: true

module LightekCommerce
  class GiftCards
    class Invalid < StandardError; end

    DENOMINATIONS = [2500, 5000, 10000, 20000].freeze
    TAX_CODE = 'txcd_10502000'
    PURCHASE = 'gift_card_purchase'
    REDEMPTION = 'gift_card_redemption'

    def self.platform_enabled? = ENV['LIGHTEK_COMMERCE_GIFT_CARDS_ENABLED'] == 'true'

    def self.enabled?(site)
      platform_enabled? && site.tenant_type == 'User' && site.manifest.to_h['commerce_gift_cards'] == true
    end

    def self.redemption_enabled?(site)
      platform_enabled? && site.tenant_type == 'User' && site.manifest.to_h.key?('commerce_gift_cards')
    end

    def self.available_balance!(site:, scope:, code:)
      digest = GiftCard.digest(code)
      card = GiftCard.find_by(site: site, store_scope: scope, livemode: GiftCheckout.live_mode?, code_digest: digest) if digest
      raise Invalid, 'This gift card is unavailable for this store.' unless card&.usable?

      card.available_cents
    end

    def self.source_store_key(site) = Digest::SHA256.hexdigest("site-#{site.id}")

    def self.network_scope(peer, key)
      raise ArgumentError, 'Invalid gift card store identity.' unless key.to_s.match?(/\A[a-f0-9]{64}\z/)

      "peer-#{peer.id}-#{key}"
    end

    def self.purchase!(site:, buyer:, customer_email:, denomination:)
      LightekAgency::Demos.ensure_live_site!(site, error: Invalid) if defined?(LightekAgency::Demos)
      raise Invalid, 'Gift card purchases are unavailable for this store.' unless enabled?(site)
      amount = Integer(denomination.to_s, 10)
      raise Invalid, 'Choose a listed gift card amount.' unless DENOMINATIONS.include?(amount)

      site.with_lock do
        product = Product.find_or_create_by!(site: site, slug: "store-gift-card-#{amount}") do |item|
          item.assign_attributes(name: "Gift card ($#{amount / 100})", price_cents: amount, product_type: 'digital',
            billing_interval: 'one_time', published: false, inventory_quantity: 0, track_inventory: false)
        end
        unless !product.published? && product.product_type == 'digital' && product.billing_interval == 'one_time' &&
            product.price_cents == amount && product.effective_hosting_package.nil?
          raise Invalid, 'This denomination needs store setup before it can be sold.'
        end

        order = Order.new(site: site, customer_email: customer_email.to_s.strip.downcase, purpose: PURCHASE,
          stock_reserved: false, storefront_buyer_id: buyer.id, subtotal_cents: amount, total_cents: amount)
        order.save!
        order.items.create!(product: product, name: "Gift card ($#{amount / 100})", quantity: 1, unit_price_cents: amount,
          line_total_cents: amount, purchase_snapshot: {'billing_interval' => 'one_time', 'product_type' => 'digital'})
        ReservationExpiryJob.set(wait: 35.minutes).perform_later(order.id)
        order
      end
    rescue ArgumentError
      raise Invalid, 'Choose a listed gift card amount.'
    end

    def self.release_hold!(order)
      return unless order.gift_card_redemption?

      redemption = GiftRedemption.find_by(order: order)
      return unless redemption&.state == 'held'
      redemption.gift_card.with_lock do
        redemption.gift_card.increment!(:available_cents, redemption.amount_cents)
        redemption.update!(state: 'released')
      end
    end
  end
end
