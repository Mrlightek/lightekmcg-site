module LightekShipping
  class Purchases
    def self.start!(quote:, email:, return_url:)
      raise ArgumentError, "This shipping quote has expired; request a new rate" if quote.expires_at <= Time.current && !quote.purchase_order
      if quote.broker_reference.present?
        client = LightekReservations::Federation::Client.new(quote.site)
        data = client.request("shipping/quotes/#{quote.broker_reference}/purchase", method: :post, body: {return_url: return_url})
        return data.fetch("url")
      end
      order = nil
      quote.with_lock do
        order = quote.purchase_order
        unless order
          operator = User.find_by!(role: "super_admin")
          platform_site = DymondSite::Site.where(tenant: operator).order(:id).first || raise(ArgumentError, "Platform billing storefront is not configured")
          product = LightekCommerce::Product.find_or_create_by!(site: platform_site, slug: "internal-shipping-label") do |item|
            item.name = "Lightek Shipping"; item.product_type = "service"; item.billing_interval = "one_time"
            item.price_cents = 0; item.inventory_quantity = 0; item.track_inventory = false; item.published = false
          end
          order = LightekCommerce::Order.create!(site: platform_site, customer_email: email, purpose: "shipping_label", stock_reserved: false,
            subtotal_cents: quote.platform_price_cents, total_cents: quote.platform_price_cents, shipping_quote: quote)
          order.items.create!(product: product, name: "#{quote.service_name} shipping label", quantity: 1,
            unit_price_cents: quote.platform_price_cents, line_total_cents: quote.platform_price_cents,
            purchase_snapshot: {"billing_interval" => "one_time", "product_type" => "service", "track_inventory" => false})
          quote.update!(purchase_order: order)
        end
      end
      if order.paid_at?
        LabelJob.perform_later(order.id)
        return return_url
      end
      stripe_test = DymondBank::StripeCredentials.secret_key.to_s.match?(/\A(?:sk|rk)_test_/)
      raise ArgumentError, "FedEx and Stripe must use the same test or production mode" unless quote.sandbox? == stripe_test
      checkout = LightekCommerce::StripeCheckout.start!(order: order, success_url: return_url, cancel_url: return_url)
      checkout.url
    end
  end
end
