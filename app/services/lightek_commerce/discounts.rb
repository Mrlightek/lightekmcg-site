# frozen_string_literal: true

module LightekCommerce
  class Discounts
    class Invalid < StandardError; end

    def self.quote(site:, products:, quantities:, code:, lock: false)
      code = Discount.normalize(code)
      return unless code || Discount.exists?(site: site, active: true, code: nil)

      eligible = products.any? && products.all? { |product| BuyerFees.eligible?(product) && product.billing_interval == 'one_time' }
      unless eligible
        raise Invalid, 'This discount applies to one-time retail purchases.' if code
        return
      end

      _, base = BuyerFees.cart_price(products: products, requested: quantities, lock: lock, price_only: true)
      subtotal = base.to_i
      candidates = Discount.where(site: site, active: true, code: code).order(:id)
      candidates = candidates.lock if lock
      best = candidates.map { |discount| [discount, discount.savings(subtotal)] }.max_by(&:last)
      return best if best && best.last.positive?

      raise Invalid, 'This discount code does not apply to your cart.' if code
    end

    def self.processor_items(order)
      items = order.items.to_a

      remaining_discount = order.discount_amount
      remaining_value = items.sum(&:line_total_cents)
      items.flat_map do |item|
        gross = item.line_total_cents
        discount = remaining_value.positive? ? remaining_discount * gross / remaining_value : 0
        remaining_discount -= discount
        remaining_value -= gross
        unit, remainder = (gross - discount).divmod(item.quantity)
        rows = [line(item, unit, item.quantity - remainder)]
        rows << line(item, unit + 1, remainder) if remainder.positive?
        rows
      end
    end

    def self.line(item, cents, quantity)
      price = {currency: item.order.currency, unit_amount: cents, product_data: {name: item.name}}
      {price_data: price, quantity: quantity}
    end
    private_class_method :line
  end
end
