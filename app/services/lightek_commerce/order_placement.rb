# frozen_string_literal: true
module LightekCommerce
  class OrderPlacement
    class Invalid < StandardError; end

    # Creates a pending order and atomically reserves local inventory.
    # The order is NEVER considered paid until a verified processor event settles it.
    def self.call(site:, customer_email:, quantities:)
      raise Invalid, "Empty cart" if quantities.blank?
      raise Invalid, "Too many line items" if quantities.size > 50
      requested = quantities.to_h.transform_keys(&:to_s)
      requested.each_key { |key| raise Invalid, "Invalid product selection" unless key.match?(/\A[1-9]\d*(?::[1-9]\d*)?\z/) }
      requested.each_value { |qty| raise Invalid, "Invalid quantity" unless qty.to_s.match?(/\A[1-9]\d*\z/) && qty.to_i <= 100 }
      Order.transaction do
        product_ids = requested.keys.map { |key| key.split(":").first.to_i }.uniq
        products = Product.where(site: site, id: product_ids).order(:id).lock.to_a
        raise Invalid, "One or more products are unavailable" unless products.size == product_ids.size && products.all?(&:published?)
        order = Order.new(site: site, customer_email: customer_email.to_s.strip.downcase)
        order.save!
        subtotal = 0
        requested.sort.each do |key, raw_quantity|
          product_id, variant_id = key.split(":").map(&:to_i)
          product = products.find { |record| record.id == product_id }
          qty = raw_quantity.to_i
          if product.product_type == "lightek_instance"
            raise Invalid, "Installation products must be purchased separately, quantity one" unless qty == 1 && requested.size == 1 && variant_id.nil?
          end
          if variant_id
            variant = ProductVariant.where(product: product, active: true).lock.find(variant_id)
            raise Invalid, "Insufficient inventory for #{product.name} / #{variant.name}" if variant.inventory_quantity < qty
            variant.update!(inventory_quantity: variant.inventory_quantity - qty)
            name = "#{product.name} / #{variant.name}"
            price = variant.price_cents
          else
            raise Invalid, "Please select a product option" if product.variants.where(active: true).exists?
            raise Invalid, "Insufficient inventory for #{product.name}" if product.inventory_quantity < qty
            product.update!(inventory_quantity: product.inventory_quantity - qty)
            name = product.name
            price = product.price_cents
          end
          line_total = price * qty
          subtotal += line_total
          order.items.create!(product: product, variant: variant_id ? variant : nil,
            name: name, quantity: qty, unit_price_cents: price, line_total_cents: line_total)
        end
        # No guessed tax or shipping: add those only through a configured quote provider.
        order.update!(subtotal_cents: subtotal, total_cents: subtotal)
        ReservationExpiryJob.set(wait: 30.minutes).perform_later(order.id)
        order
      end
    rescue ArgumentError, TypeError
      raise Invalid, "Invalid cart items"
    end

    def self.cancel!(order)
      order.with_lock do
        return order if order.status == "canceled"
        raise Invalid, "Only unpaid orders can release reserved stock" unless order.status == "pending_payment"
        order.items.order(:product_id).each do |item|
          if item.variant_id.present?
            variant = ProductVariant.lock.find(item.variant_id)
            variant.update!(inventory_quantity: variant.inventory_quantity + item.quantity)
          else
            product = Product.lock.find(item.product_id)
            product.update!(inventory_quantity: product.inventory_quantity + item.quantity)
          end
        end
        order.update!(status: "canceled", canceled_at: Time.current)
      end
      order
    end
  end
end
