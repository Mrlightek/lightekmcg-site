require "ostruct"
require "digest"
module LightekCommerce
  class NetworkCheckout
    def self.connected?(order)
      LightekReservations::Federation::Client.config(order.site).present? && order.network_sale.nil? &&
        order.purpose.to_s.in?(["", "purchase"]) && order.items.none? { |item| item.product.product_type == "lightek_instance" }
    end
    def self.chain(site, merchant: site.tenant)
      raise ArgumentError, "Merchant must be a business account" unless merchant.is_a?(User)
      users = [merchant] + merchant.account_ancestors
      host = ENV["LIGHTEK_DEPLOYED_SITE_HOST"].presence
      root = host && DymondSite::Site.find_by(host: host)&.tenant
      users = users.take(users.index(root) + 1) if root && users.include?(root)
      users << root if root && !users.include?(root)
      users.reverse.map { |user| {"subject" => "user-#{user.id}", "email" => user.email_address, "first_name" => user.first_name,
        "last_name" => user.last_name, "role" => user.role, "upstream_share_bps" => user.upstream_share_bps} }
    end
    def self.start!(order:, embedded: false)
      config = LightekReservations::Federation::Client.config(order.site)
      host = config["client_host"].presence || ENV["LIGHTEK_DEPLOYED_SITE_HOST"].presence || order.site.host
      return_url = "https://#{host}/commerce/shop?#{URI.encode_www_form(site_id: order.site_id, order_id: order.id)}"
      attributes = {source_key: Digest::SHA256.hexdigest("#{order.payment_namespace}:#{order.id}"), customer_email: order.customer_email,
        store_name: order.site.name, merchant_chain: chain(order.site), return_url: return_url,
        items: order.items.map { |item| {name: item.name, quantity: item.quantity, unit_price_cents: item.unit_price_cents,
          product_type: item.purchase_snapshot.fetch("product_type", item.product.product_type),
          billing_interval: item.purchase_snapshot.fetch("billing_interval", "one_time")} }}
      if order.shipping_quote
        raise StripeCheckout::Unavailable, "Shipping quote is not connected to the network" if order.shipping_quote.broker_reference.blank?
        attributes[:shipping_quote_key] = order.shipping_quote.broker_reference
        attributes[:shipping_price_cents] = order.shipping_quote.customer_price_cents
      end
      attributes[:buyer_price_cents] = order.buyer_fee_breakdown.fetch('buyer_cents') if order.buyer_fee_cents.positive?
      attributes[:discount_cents] = order.discount_amount if order.discount_amount.positive?
      attributes[:embedded] = true if embedded
      result = client(order).request("commerce/checkouts", method: :post, body: {checkout: attributes})
      if order.buyer_fee_cents.positive? && result['buyer_fee_cents'] != order.buyer_fee_cents
        raise StripeCheckout::Unavailable, 'The checkout could not confirm the price shown in your cart.'
      end

      reference = result.fetch("key")
      url = result['url']
      if url.present?
        uri = URI.parse(url)
        raise StripeCheckout::Unavailable, "Invalid network checkout destination" unless uri.is_a?(URI::HTTPS) && !uri.userinfo &&
          uri.port == 443 && (uri.host == "checkout.stripe.com" || uri.host == host)
      elsif !embedded || result['embedded'] != true || !reference.to_s.match?(/\A[a-f0-9-]{36}\z/)
        raise StripeCheckout::Unavailable, 'Network checkout did not confirm a payment session.'
      end
      order.update!(payment_provider: "network", payment_reference: reference, network_reference: reference)
      OpenStruct.new(id: reference, url: uri&.to_s)
    rescue LightekReservations::Federation::Client::Unavailable, ArgumentError => error
      raise StripeCheckout::Unavailable, error.message
    end
    def self.embedded_session!(order)
      reference = order.network_reference.to_s
      unless order.payment_provider == 'network' && reference.match?(/\A[a-f0-9-]{36}\z/)
        raise StripeCheckout::Unavailable, 'This order does not have an embedded payment session.'
      end

      result = client(order).request("commerce/orders/#{reference}/embedded-checkout", method: :post)
      secret = result['client_secret']
      key = result['publishable_key']
      unless result['key'] == reference && secret.is_a?(String) && secret.start_with?('cs_') &&
          key.is_a?(String) && key.match?(/\Apk_(?:live|test)_/)
        raise StripeCheckout::Unavailable, 'The embedded payment session could not be verified.'
      end

      [OpenStruct.new(client_secret: secret), key]
    rescue LightekReservations::Federation::Client::Unavailable => error
      raise StripeCheckout::Unavailable, error.message
    end

    def self.client(order) = LightekReservations::Federation::Client.new(order.site)
    def self.action!(order:, action:, attributes: {})
      values = attributes.merge(invoice_reference: order.network_invoice_reference)
      result = client(order).request("commerce/orders/#{order.network_reference}/#{action}", method: :post, body: values)
      synchronize!(order)
      result
    end
    def self.synchronize!(order)
      return order if order.network_reference.blank?
      root = order.network_invoice_reference.present? ? Order.find_by!(site: order.site, network_reference: order.network_reference, network_invoice_reference: nil) : order
      receipt = client(root).request("commerce/orders/#{root.network_reference}").deep_stringify_keys
      root.with_lock do
        raise StripeCheckout::Unavailable, "Network receipt does not match the reserved merchandise" unless receipt.fetch("subtotal_cents") == root.subtotal_cents
        if root.buyer_fee_cents.positive? && (receipt['buyer_fee_cents'] != root.buyer_fee_cents ||
            receipt['total_cents'] != root.subtotal_cents + root.buyer_fee_cents + receipt.fetch('tax_cents') + receipt.fetch('shipping_cents'))
          raise StripeCheckout::Unavailable, 'Network receipt does not match the confirmed buyer price.'
        end
        apply_order!(root, receipt)
        if (data = receipt["subscription"])
          subscription = root.commerce_subscription || Subscription.new(order: root)
          subscription.assign_attributes(data.slice("processor_reference", "customer_reference", "status", "billing_interval", "amount_cents", "currency", "current_period_end", "cancel_at_period_end"))
          subscription.save!
          Array(receipt["invoices"]).each do |invoice|
            local_invoice = BillingInvoice.find_or_initialize_by(processor_reference: invoice.fetch("reference"))
            if local_invoice.persisted? && local_invoice.subscription_id != subscription.id
              raise StripeCheckout::Unavailable, "Network invoice belongs to another subscription"
            end
            settled_order = local_invoice.settlement_order || (invoice["initial"] ? root : nil)
            if invoice["order"] && !invoice["initial"] && !settled_order
              row = invoice.fetch("order")
              if root.buyer_fee_cents.positive? && (row['subtotal_cents'] != root.subtotal_cents ||
                  row['buyer_fee_cents'] != root.buyer_fee_cents ||
                  row['total_cents'] != root.subtotal_cents + root.buyer_fee_cents + row.fetch('tax_cents'))
                raise StripeCheckout::Unavailable, 'Network renewal does not match the confirmed buyer price.'
              end
              settled_order = Order.create!(site: root.site, customer_email: root.customer_email, purpose: "subscription_renewal", stock_reserved: false,
                payment_provider: "network", payment_reference: root.network_reference, network_reference: root.network_reference,
                network_invoice_reference: invoice.fetch("reference"), buyer_fee_snapshot: root.buyer_fee_breakdown, subtotal_cents: row.fetch("subtotal_cents"), total_cents: row.fetch("total_cents"))
              source = root.items.sole
              settled_order.items.create!(product: source.product, name: source.name, quantity: 1,
                unit_price_cents: row.fetch("subtotal_cents"), line_total_cents: row.fetch("subtotal_cents"), purchase_snapshot: source.purchase_snapshot)
            end
            apply_order!(settled_order, invoice.fetch("order")) if settled_order && invoice["order"] && !invoice["initial"]
            local_invoice.assign_attributes(subscription: subscription, settlement_order: settled_order, amount_paid_cents: invoice.fetch("amount_paid_cents"), currency: "usd", paid_at: invoice.fetch("paid_at"))
            local_invoice.save!
          end
        end
      end
      order.reload
    end
    def self.apply_order!(order, receipt)
      if receipt["status"] == "canceled" && order.status == "pending_payment"
        OrderPlacement.cancel!(order)
      else
        values = receipt.slice("status", "shipping_cents", "tax_cents", "total_cents", "refunded_cents", "paid_at", "fulfilled_at", "fulfillment_reference", "merchant_transfer_ref", "merchant_transfer_amount_cents")
        order.update!(values)
      end
    end
  end
end
