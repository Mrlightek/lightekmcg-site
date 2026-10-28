# frozen_string_literal: true
module LightekCommerce
  class OrderPlacement
    class Invalid < StandardError; end

    # Creates a pending order and atomically reserves local inventory.
    # The order is NEVER considered paid until a verified processor event settles it.
    def self.call(site:, customer_email:, quantities:)
      raise Invalid, "Empty cart" if quantities.blank?
      raise Invalid, "Too many line items" if quantities.size > 50
      requested = quantities.to_h.transform_keys { |key| Integer(key, 10) }
      requested.each_value { |qty| raise Invalid, "Invalid quantity" unless qty.to_s.match?(/\A[1-9]\d*\z/) && qty.to_i <= 100 }
      Order.transaction do
        products = Product.where(site: site, id: requested.keys).order(:id).lock.to_a
        raise Invalid, "One or more products are unavailable" unless products.size == requested.size && products.all?(&:published?)
        order = Order.new(site: site, customer_email: customer_email.to_s.strip.downcase)
        order.save!
        subtotal = 0
        products.each do |product|
          qty = requested.fetch(product.id).to_i
          raise Invalid, "Insufficient inventory for #{product.name}" if product.inventory_quantity < qty
          product.update!(inventory_quantity: product.inventory_quantity - qty)
          line_total = product.price_cents * qty
          subtotal += line_total
          order.items.create!(product: product, name: product.name, quantity: qty, unit_price_cents: product.price_cents, line_total_cents: line_total)
        end
        # No guessed tax or shipping: add those only through a configured quote provider.
        order.update!(subtotal_cents: subtotal, total_cents: subtotal)
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
          product = Product.lock.find(item.product_id)
          product.update!(inventory_quantity: product.inventory_quantity + item.quantity)
        end
        order.update!(status: "canceled", canceled_at: Time.current)
      end
      order
    end
  end
end
