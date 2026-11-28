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
    def self.create!(site:, origin:, recipient:, packages:, fingerprint: nil, customer_markup_bps: 0, gateway: true, merchandise_return: nil)
      payload = Payload.shipment!(origin: origin, recipient: recipient, packages: packages)
      network = gateway && LightekReservations::Federation::Client.config(site)
      rates = if network
        data = LightekReservations::Federation::Client.new(site).request("shipping/quotes", method: :post,
          body: {origin: origin, recipient: recipient, packages: packages})
        data.fetch("quotes").map do |rate|
          rate.slice("service_code", "service_name", "sandbox").merge("provider" => rate.fetch("provider", "fedex"),
            "broker_reference" => rate.fetch("key"), "platform_price_cents" => rate.fetch("price_cents"),
            "expires_at" => Time.iso8601(rate.fetch("expires_at")))
        end
      else
        platform_rates(payload)
      end
      raise ArgumentError, 'No carrier returned an eligible account rate for this delivery.' if rates.empty?

      Quote.transaction do
        rates.sort_by { |rate| rate.fetch("platform_price_cents") }.map do |rate|
          price = rate.fetch("platform_price_cents")
          customer_price = rate.fetch("provider") == "ups" ? price : (price * (10_000 + customer_markup_bps) + 9999) / 10_000
          rate['merchandise_return_id'] = merchandise_return.id if merchandise_return
          Quote.create!(rate.merge(site: site, customer_price_cents: customer_price, cart_fingerprint: fingerprint, shipment_payload: payload))
        end
      end
    end

    def self.platform_rates(payload)
      Account.where(enabled: true).order(:provider).flat_map do |account|
        account.carrier_class.new(account: account).rates(payload).map do |rate|
          cost = rate.fetch("cost_cents")
          rate.slice("service_code", "service_name").merge("provider" => account.provider, "sandbox" => account.sandbox?,
            "carrier_cost_cents" => cost, "platform_price_cents" => account.retail_cents(cost), "expires_at" => 30.minutes.from_now)
        end
      rescue Fedex::Unavailable, Ups::Unavailable, LightekVault::Service::AccessDenied, ActiveRecord::RecordNotFound
        []
      end
    end
    private_class_method :platform_rates
  end
end
