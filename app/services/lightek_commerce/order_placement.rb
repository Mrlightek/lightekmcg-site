# frozen_string_literal: true
module LightekCommerce
  class OrderPlacement
    class Invalid < StandardError; end

    # Creates a pending order and atomically reserves local inventory.
    # The order is NEVER considered paid until a verified processor event settles it.
    def self.call(site:, customer_email:, quantities:, shipping_quote: nil, growth_visit: nil, buyer: nil, communications_peer: nil, full_package_offer: nil, workspace_seats: nil, buyer_fee_token: nil, storefront: false, discount_code: nil, expected_discount_cents: nil, discount_review_token: nil, shipping_review_token: nil, shipping_discount_code: nil, storefront_buyer: nil, gift_redemption: false)
      LightekAgency::Demos.ensure_live_site!(site, error: Invalid) if defined?(LightekAgency::Demos)
      raise Invalid, "Empty cart" if quantities.blank?
      raise Invalid, "Too many line items" if quantities.size > 50
      requested = quantities.to_h.transform_keys(&:to_s)
      requested.each_key { |key| raise Invalid, "Invalid product selection" unless key.match?(/\A[1-9]\d*(?::[1-9]\d*)?\z/) }
      requested.each_value { |qty| raise Invalid, "Invalid quantity" unless qty.to_s.match?(/\A[1-9]\d*\z/) && qty.to_i <= 100 }
      Order.transaction do
        if shipping_quote
          shipping_quote.lock!
          raise Invalid, "Shipping quote does not match this cart" unless shipping_quote.site_id == site.id && shipping_quote.expires_at > Time.current &&
            shipping_quote.cart_fingerprint == LightekShipping::Quotes.fingerprint(site, requested)
        end
        if buyer && buyer.email_address != customer_email.to_s.strip.downcase
          raise Invalid, "Buyer does not match checkout identity"
        end
        product_ids = requested.keys.map { |key| key.split(":").first.to_i }.uniq
        products = Product.where(site: site, id: product_ids).order(:id).lock.to_a
        raise Invalid, "One or more products are unavailable" unless products.size == product_ids.size && products.all?(&:published?)
        if gift_redemption && (!storefront || !GiftCards.redemption_enabled?(site) || products.any? { |product|
          !BuyerFees.eligible?(product) || product.billing_interval != 'one_time'
        })
          raise Invalid, 'Gift cards apply to one-time retail purchases at participating stores.'
        end
        if workspace_seats && (requested.size != 1 || requested.keys.first.include?(":") ||
          !defined?(Gatekeeper::Hosting::WorkspacePlans))
          raise Invalid, "Choose one Workspace plan"
        end
        normalized_email = customer_email.to_s.strip.downcase
        reviewed_key = if storefront && storefront_buyer && (discount_review_token.present? || shipping_review_token.present?)
          identity = [discount_review_token, storefront_buyer.id, gift_redemption, shipping_quote&.id, requested.transform_values(&:to_i).sort]
          identity << shipping_review_token if shipping_review_token.present?
          Digest::SHA256.hexdigest(identity.to_json)
        end
        if reviewed_key
          existing = Order.find_by(site: site, customer_email: normalized_email, client_checkout_key: reviewed_key)
          next existing if existing
        end
        fee_snapshot = if storefront && (buyer_fee_token.present? || ENV['LIGHTEK_COMMERCE_BUYER_FEE_HOSTS'].present?)
          BuyerFees.snapshot_for(site: site, products: products, requested: requested.transform_values(&:to_i),
            token: buyer_fee_token)
        else
          {}
        end
        discount = if storefront && (discount_code.present? || !expected_discount_cents.nil?)
          storefront_discount(site: site, products: products, quantities: requested, code: discount_code, buyer_id: storefront_buyer&.id)
        end
        savings = discount&.total.to_i
        if !expected_discount_cents.nil? && savings != Integer(expected_discount_cents.to_s, 10)
          raise Invalid, 'The discount changed. Review your cart before continuing.'
        end
        if discount_review_token.present? && !Discounts.matches_review?(site, discount, discount_review_token)
          raise Invalid, 'The reviewed discount expired or changed. Review your cart before continuing.'
        end
        if fee_snapshot.present? && savings.to_i.positive?
          fee_snapshot = BuyerFees.quote_amount(fee_snapshot.fetch('merchant_cents') - savings)
        end
        shipping_discount = 0
        if storefront && shipping_quote
          if ShippingPromotion.settings(site)['enabled'] == true && products.any? { |product| product.product_type == 'physical' } &&
              products.all? { |product| BuyerFees.eligible?(product) && product.billing_interval == 'one_time' }
            _, merchandise = BuyerFees.cart_price(products: products, requested: requested, lock: true, price_only: true)
            shipping_discount = ShippingPromotion.savings(site: site, quote: shipping_quote, subtotal: merchandise - savings,
              buyer_fee: fee_snapshot, merchandise_discount: discount, code: shipping_discount_code)
          end
          unless ShippingPromotion.valid_review?(site, shipping_quote, shipping_discount, shipping_review_token)
            raise Invalid, 'The delivery price changed. Review the shipping options before continuing.'
          end
        end
        order = Order.new(shipping_quote: shipping_quote, site: site, customer_email: normalized_email)
        order.shipping_discount_cents = shipping_discount if shipping_discount.positive?
        order.client_checkout_key = reviewed_key if reviewed_key
        order.purpose = GiftCards::REDEMPTION if gift_redemption
        order.storefront_buyer_id = storefront_buyer.id if storefront && storefront_buyer
        if discount
          order.discount_cents = savings
          order.discount_name = discount.names.join(", ").truncate(255)
        end
        if fee_snapshot.present?
          order.buyer_fee_snapshot = fee_snapshot
          unless reviewed_key
            checkout_identity = [buyer_fee_token]
            checkout_identity << "buyer=#{storefront_buyer.id}" if storefront && storefront_buyer
            checkout_identity << 'gift' if gift_redemption
            checkout_identity << Digest::SHA256.hexdigest(discount.identity.to_json) if discount
            order.client_checkout_key = Digest::SHA256.hexdigest(checkout_identity.join(':'))
            existing = Order.find_by(site: site, customer_email: order.customer_email, client_checkout_key: order.client_checkout_key)
            next existing if existing
          end
        end
        if shipping_quote && (shipping_quote.purchase_order_id.present? ||
            Order.where(shipping_quote: shipping_quote).where("purpose IS NULL OR purpose <> ?", "shipping_label").exists?)
          raise Invalid, "This shipping quote already has a checkout"
        end
        order.growth_visit = growth_visit if growth_visit
        order.save!
        Discounts.record!(order, discount, buyer_id: storefront_buyer&.id) if discount
        recurring = products.select { |product| product.billing_interval != "one_time" }
        raise Invalid, "Buy each subscription separately, quantity one" if recurring.any? && (requested.size != 1 || requested.values.first.to_i != 1 || requested.keys.first.include?(":"))
        subtotal = 0
        requested.sort.each do |key, raw_quantity|
          product_id, variant_id = key.split(":").map(&:to_i)
          product = products.find { |record| record.id == product_id }
          qty = raw_quantity.to_i
          if product.product_type == "lightek_instance"
            raise Invalid, "Installation products must be purchased separately, quantity one" unless qty == 1 && requested.size == 1 && variant_id.nil?
          end
          direct_package = nil
          if variant_id
            variant = ProductVariant.where(product: product, active: true).lock.find(variant_id)
            raise Invalid, "Insufficient inventory for #{product.name} / #{variant.name}" if variant.inventory_quantity < qty
            variant.update!(inventory_quantity: variant.inventory_quantity - qty)
            name = "#{product.name} / #{variant.name}"
            price = variant.price_cents
          else
            raise Invalid, "Please select a product option" if product.variants.where(active: true).exists?
            raise Invalid, "Insufficient inventory for #{product.name}" if product.track_inventory? && product.inventory_quantity < qty
            product.update!(inventory_quantity: product.inventory_quantity - qty) if product.track_inventory?
            name = product.name
            price = product.price_cents
            if buyer&.role == 'white_label' && (direct_package = product.hosting_package) && product.site.tenant&.role == 'super_admin'
              direct_package.lock!
              price = direct_package.agency_wholesale_cents
            end
          end
          workspace = Gatekeeper::Hosting::WorkspacePlans if defined?(Gatekeeper::Hosting::WorkspacePlans)
          seat_range = workspace.seats_for(product) if workspace && product.product_type == "lightek_instance"
          if seat_range
            seats = workspace_seats.nil? ? seat_range.begin : workspace_seats
            limit = workspace.checkout_seat_limit(starting_price: price, seat_range: seat_range)
            unless seats.is_a?(Integer) && seats.between?(seat_range.begin, limit)
              raise Invalid, "Choose a seat count offered by this Workspace plan"
            end

            name = "#{name} (#{seats} #{seats == 1 ? 'seat' : 'seats'})"
            price = workspace.monthly_price(starting_price: price, seats: seats, seat_range: seat_range)
          elsif workspace_seats
            raise Invalid, "Choose a Workspace plan"
          end
          line_total = price * qty
          subtotal += line_total
          snapshot = {"product_type" => product.product_type, "billing_interval" => product.billing_interval,
            "track_inventory" => variant_id ? true : product.track_inventory?, "subscription_plan_id" => product.subscription_plan_id}
          if discount
            allocation = discount.line_savings.fetch(key, 0)
            snapshot['merchandise_discount_cents'] = allocation if allocation.positive?
          end
          kind = product.communications_kind
          snapshot["communications_kind"] = kind if kind
          snapshot["voice_plan"] = product.slug if kind == "voice"
          if product.full_communications_package?
            unless buyer && full_package_offer && full_package_offer == LightekCommunications::FullPackageCheckout.offer(product) &&
                price == product.price_cents
              raise Invalid, "Choose this package from CMS signup."
            end
            snapshot["communications_kind"] = "voice"
            snapshot["cellular_bundle"] = full_package_offer.slice("data_limit_mb")
          end
          if product.cellular_voice_bundle?
            bundle = LightekCommunications::CellularBundle.offer(product, peer: communications_peer)
            unless bundle && communications_peer.merchant.email_address.to_s.strip.downcase == order.customer_email
              raise Invalid, "This plan can only be ordered from an eligible installation's communications workspace"
            end
            snapshot["cellular_bundle"] = bundle.slice("data_limit_mb")
          end
          snapshot["workspace_seats"] = seats if seat_range
          package = product.respond_to?(:effective_hosting_package) ? product.effective_hosting_package : product.hosting_package
          snapshot["pricing_tier"] = "agency_wholesale" if direct_package
          if package
            raise Invalid, "Hosting package is unavailable" unless package.active?
            raise Invalid, "Hosting package is unavailable" unless package.product.published?
            snapshot["hosting"] = package.snapshot
            if product.respond_to?(:source_hosting_package_id) && product.source_hosting_package_id
              package.product.lock!
              package.lock!
              floor = package.agency_wholesale_cents
              raise Invalid, "Update this offer: its price no longer covers the Lightek package" if price < package.agency_minimum_price_cents
              snapshot["hosting"]["platform_charge_cents"] = floor
              snapshot["hosting"]["source_product_id"] = package.product_id
            end
          end
          if product.product_type == "lightek_instance" && defined?(LightekAgency::PackagePolicy) && product.has_attribute?(:package_policy)
            policy = LightekAgency::PackagePolicy.for_product(product)
            policy.fetch("limits")["max_users"] = seats if seat_range
            snapshot["managed_package"] = {"source_key" => "#{order.payment_namespace}:#{order.id}", "policy" => policy}
            snapshot["managed_package"]["policy_digest"] = LightekAgency::PackagePolicy.digest(snapshot["managed_package"]["policy"])
          end
          order.items.create!(purchase_snapshot: snapshot, product: product, variant: variant_id ? variant : nil,
            name: name, quantity: qty, unit_price_cents: price, line_total_cents: line_total)
        end
        subtotal -= savings.to_i
        # No guessed tax or shipping: add those only through a configured quote provider.
        if fee_snapshot.present? && (order.revenue_share_snapshot.present? || fee_snapshot.fetch('merchant_cents') != subtotal)
          raise Invalid, 'This sale is no longer eligible for buyer-paid fees. Review the cart.'
        end
        shipping_cents = order.quoted_shipping_charge_cents
        order.update!(subtotal_cents: subtotal, shipping_cents: shipping_cents,
          total_cents: subtotal + shipping_cents + order.buyer_fee_cents)
        if order.revenue_share_snapshot.present? || shipping_discount.positive?
          MerchantPayouts.fee_quote(order, gross_cents: (order.total_cents * 125 + 99) / 100)
        end
        ReservationExpiryJob.set(wait: 30.minutes).perform_later(order.id)
        order
      end
    rescue ActiveRecord::RecordInvalid, RevenueSharing::Invalid, MerchantPayouts::Invalid, LightekAgency::PackagePolicy::Denied => error
      raise Invalid, error.message
    rescue ArgumentError, TypeError
      raise Invalid, "Invalid cart items"
    end

    def self.storefront_discount(site:, products:, quantities:, code:, buyer_id:)
      Discounts.quote(site: site, products: products, quantities: quantities, code: code, buyer_id: buyer_id, lock: true)
    rescue Discounts::Invalid => error
      raise Invalid, error.message
    end
    private_class_method :storefront_discount

    def self.cancel!(order)
      order.with_lock do
        return order if order.status == "canceled"
        raise Invalid, "Only unpaid orders can release reserved stock" unless order.status == "pending_payment"
        order.items.order(:product_id).each do |item|
          next unless order.stock_reserved?
          next if item.purchase_snapshot.to_h["track_inventory"] == false
          if item.variant_id.present?
            variant = ProductVariant.lock.find(item.variant_id)
            variant.update!(inventory_quantity: variant.inventory_quantity + item.quantity)
          else
            product = Product.lock.find(item.product_id)
            product.update!(inventory_quantity: product.inventory_quantity + item.quantity)
          end
        end
        GiftCards.release_hold!(order) if order.gift_card_redemption? && order.payment_provider != 'network'
        order.update!(status: "canceled", canceled_at: Time.current)
      end
      order
    end
  end
end
