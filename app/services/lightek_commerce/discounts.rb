# frozen_string_literal: true

module LightekCommerce
  class Discounts
    class Invalid < StandardError; end
    MAX_CODES = 5
    CHECKOUT_MINIMUM_CENTS = 50
    Quote = Struct.new(:entries, :line_savings, :cart_lines, :codes, keyword_init: true) do
      def total = entries.sum(&:last)
      def names = entries.map { |rule, _| rule.name }
      def identity = [cart_lines, codes, entries.map { |rule, cents| [rule.id, rule.name, cents] }, line_savings]
    end

    def self.codes(value)
      normalized = Array(value).map { |entry| Discount.normalize(entry) }.compact.uniq
      if normalized.size > MAX_CODES || normalized.any? { |entry| !entry.match?(/\A[A-Z0-9_-]{1,40}\z/) }
        raise Invalid, "Enter up to #{MAX_CODES} valid discount codes."
      end

      normalized.sort
    end

    def self.quote(site:, products:, quantities:, code:, buyer_id: nil, lock: false)
      entered = codes(code)
      return unless entered.any? || Discount.exists?(site: site, active: true, code: nil)

      unless products.any? && products.all? { |product| BuyerFees.eligible?(product) && product.billing_interval == 'one_time' }
        raise Invalid, 'These discounts apply to one-time retail purchases.' if entered.any?
        return
      end

      lines, subtotal = BuyerFees.cart_price(products: products, requested: quantities, lock: lock, price_only: true)
      prices = lines.to_h { |key, quantity, price, _| [key, quantity * price] }
      grouped = prices.keys.group_by { |key| key.split(':').first.to_i }
      scope = Discount.where(site: site, active: true, code: [nil, *entered]).order(:id)
      scope = scope.lock if lock
      now = Time.current
      candidates = scope.includes(:customer_segment).to_a
      history = CustomerSegment.history_for(site, buyer_id) if candidates.any?(&:customer_segment_id)
      candidates.select! do |rule|
        audience = rule.customer_segment_id.nil? || rule.customer_segment&.includes_history?(history)
        audience && rule.scheduled_for?(now) && subtotal >= rule.minimum_cents && within_limits?(rule, buyer_id, lock)
      end
      targets = candidates.to_h do |rule|
        [rule.id, matching_lines(grouped, rule.target_product_id, rule.target_collection)]
      end
      rewards = {}
      candidates.select(&:quantity_promotion?).each do |rule|
        target = targets[rule.id] || []
        qualifying = matching_lines(grouped, rule.qualifying_product_id, rule.qualifying_collection) || target
        rewards[rule.id] = QuantityPromotion.savings(rule, lines, qualifying, target)
        targets[rule.id] = rewards.fetch(rule.id).keys
      end
      candidates.reject! { |rule| targets[rule.id] == [] }
      explicit, automatic = candidates.partition { |rule| rule.code.present? }
      unless explicit.map(&:code).sort == entered
        raise Invalid, 'One or more discount codes do not apply to your cart.'
      end
      if explicit.many? && (!explicit.all?(&:combinable?) || explicit.flat_map { |rule| targets[rule.id] || [] }.tally.values.any? { |count| count > 1 })
        raise Invalid, 'These discount codes cannot be combined.'
      end

      winning = if explicit.none?
        sets = automatic.map { |rule| [rule] }
        sets << compatible_rules([], automatic, prices, targets, rewards, subtotal)
        sets.map { |rules| apply(rules, prices, targets, rewards, subtotal) }.max_by { |entries, _| entries.sum(&:last) }
      else
        rules = explicit.all?(&:combinable?) ? compatible_rules(explicit, automatic, prices, targets, rewards, subtotal) : explicit
        apply(rules, prices, targets, rewards, subtotal)
      end

      entries, allocated = winning
      unless explicit.all? { |rule| entries.any? { |applied_rule, _| applied_rule.id == rule.id } }
        raise Invalid, 'One or more discount codes produce no savings on this cart.'
      end
      Quote.new(entries: entries, line_savings: allocated, cart_lines: lines, codes: entered) if entries.any?
    end

    def self.signed_quote(site, quote)
      verifier.generate([site.id, quote.identity, SecureRandom.hex(12)], expires_in: 15.minutes)
    end

    def self.matches_review?(site, quote, token)
      reviewed = verifier.verified(token.to_s)
      quote && reviewed.is_a?(Array) && reviewed.first(2) == [site.id, quote.identity]
    end

    def self.record!(order, quote, buyer_id:)
      quote.entries.each do |rule, amount|
        DiscountUse.create!(order: order, discount: rule, buyer_id: buyer_id, amount_cents: amount)
      end
    end

    def self.processor_items(order)
      items = order.items.to_a
      frozen = items.any? { |item| item.purchase_snapshot.to_h.key?('merchandise_discount_cents') }
      allocations = if frozen
        items.to_h { |item| [item.id, item.purchase_snapshot.to_h.fetch('merchandise_discount_cents', 0)] }
      else
        allocate(order.discount_amount, items.to_h { |item| [item.id, item.line_total_cents] })
      end
      unless allocations.values.sum == order.discount_amount &&
          items.all? { |item| allocations.fetch(item.id, 0).between?(0, item.line_total_cents) }
        raise Invalid, 'Recorded discounts do not match this order.'
      end

      items.flat_map do |item|
        unit, remainder = (item.line_total_cents - allocations.fetch(item.id, 0)).divmod(item.quantity)
        result = [line(item, unit, item.quantity - remainder)]
        result << line(item, unit + 1, remainder) if remainder.positive?
        result
      end
    end

    def self.within_limits?(rule, buyer_id, checkout)
      return true unless rule.usage_limit || rule.buyer_limit

      uses = DiscountUse.counted.where(discount: rule)
      return false if rule.usage_limit && uses.count >= rule.usage_limit
      return true unless rule.buyer_limit
      return !checkout unless buyer_id

      uses.where(buyer_id: buyer_id).count < rule.buyer_limit
    end

    def self.matching_lines(grouped, product_id, collection)
      if collection
        ids = collection.products.where(id: grouped.keys).pluck(:id)
        grouped.values_at(*ids).flatten.sort
      elsif product_id
        grouped.fetch(product_id, [])
      end
    end

    def self.compatible_rules(explicit, automatic, prices, targets, rewards, subtotal)
      targeted, cart_offers = automatic.select(&:combinable?).partition { |rule| targets[rule.id] }
      used = explicit.flat_map { |rule| targets[rule.id] || [] }
      selected = targeted.sort_by do |rule|
        base = prices.values_at(*targets.fetch(rule.id)).sum
        savings = rewards[rule.id]&.values&.sum || rule.savings(base, cart_subtotal: subtotal)
        [-savings, rule.id]
      end.select do |rule|
        keys = targets.fetch(rule.id)
        next false if used.intersect?(keys)

        used.concat(keys)
        true
      end
      explicit + selected + cart_offers
    end

    def self.apply(rules, prices, targets, rewards, subtotal)
      products, orders = rules.partition { |rule| targets[rule.id] }
      remaining = prices.dup
      entries = []
      order_base = nil
      (products + orders).each do |rule|
        target = targets[rule.id]
        available = target ? remaining.slice(*target) : remaining
        base = target ? available.values.sum : (order_base ||= remaining.values.sum)
        cap = [remaining.values.sum - CHECKOUT_MINIMUM_CENTS, available.values.sum].min
        reward = rewards[rule.id]
        savings = reward ? reward.values.sum : rule.savings(base, cart_subtotal: subtotal)
        amount = [savings, cap].min
        next unless amount.positive?

        allocate(amount, reward || available).each { |key, cents| remaining[key] -= cents }
        entries << [rule, amount]
      end
      [entries, prices.to_h { |key, gross| [key, gross - remaining.fetch(key)] }]
    end

    def self.allocate(amount, prices)
      total = prices.values.sum
      prices.to_h do |key, gross|
        portion = total.positive? ? amount * gross / total : 0
        amount -= portion
        total -= gross
        [key, portion]
      end
    end

    def self.line(item, cents, quantity)
      {price_data: {currency: item.order.currency, unit_amount: cents, product_data: {name: item.name}}, quantity: quantity}
    end

    def self.verifier
      Rails.application.message_verifier('commerce-discount-review-v1')
    end
    private_class_method :line, :within_limits?, :matching_lines, :compatible_rules, :apply, :allocate, :verifier
  end
end
