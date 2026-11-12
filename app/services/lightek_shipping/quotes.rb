require "digest"
module LightekShipping
  class Quotes
    def self.fingerprint(site, quantities)
      Digest::SHA256.hexdigest(JSON.generate([site.host, quantities.to_h.stringify_keys.sort]))
    end
    def self.for_cart!(site:, quantities:, recipient:)
      profile = Profile.find_by!(site: site)
      packages = []
      quantities.to_h.each do |selection, count|
        raise ArgumentError, "Invalid product selection" unless selection.to_s.match?(/\A[1-9]\d*(?::[1-9]\d*)?\z/) && count.to_s.match?(/\A[1-9]\d*\z/)
        product = LightekCommerce::Product.visible.where(site: site).find(selection.to_s.split(":").first)
        next unless product.product_type == "physical"
        raise ArgumentError, "At most 40 physical items can be shipped in one checkout" if packages.size + count.to_i > 40
        dimensions = profile.default_package.to_h.merge({"weight_lb" => product.shipping_weight_lb,
          "length_in" => product.shipping_length_in, "width_in" => product.shipping_width_in, "height_in" => product.shipping_height_in}.compact)
        count.to_i.times { packages << dimensions }
      end
      raise ArgumentError, "This cart does not need shipping" if packages.empty?
      create!(site: site, origin: profile.origin, recipient: recipient, packages: packages,
        fingerprint: fingerprint(site, quantities), customer_markup_bps: profile.customer_markup_bps)
    end
    def self.create!(site:, origin:, recipient:, packages:, fingerprint: nil, customer_markup_bps: 0, gateway: true)
      payload = Payload.shipment!(origin: origin, recipient: recipient, packages: packages)
      network = gateway && LightekReservations::Federation::Client.config(site)
      if network
        data = LightekReservations::Federation::Client.new(site).request("shipping/quotes", method: :post,
          body: {origin: origin, recipient: recipient, packages: packages})
        data.fetch("quotes").map do |rate|
          price = rate.fetch("price_cents")
          Quote.create!(site: site, broker_reference: rate.fetch("key"), service_code: rate.fetch("service_code"), service_name: rate.fetch("service_name"),
            platform_price_cents: price, customer_price_cents: (price * (10_000 + customer_markup_bps) + 9999) / 10_000,
            sandbox: rate.fetch("sandbox"), shipment_payload: payload, cart_fingerprint: fingerprint, expires_at: Time.iso8601(rate.fetch("expires_at")))
        end
      else
        account = Account.find_by!(provider: "fedex", enabled: true)
        Fedex.new(account: account).rates(payload).map do |rate|
          price = account.retail_cents(rate.fetch("cost_cents"))
          Quote.create!(site: site, service_code: rate.fetch("service_code"), service_name: rate.fetch("service_name"),
            carrier_cost_cents: rate.fetch("cost_cents"), platform_price_cents: price,
            customer_price_cents: (price * (10_000 + customer_markup_bps) + 9999) / 10_000,
            sandbox: account.sandbox?, shipment_payload: payload, cart_fingerprint: fingerprint, expires_at: 30.minutes.from_now)
        end
      end
    end
  end
end
