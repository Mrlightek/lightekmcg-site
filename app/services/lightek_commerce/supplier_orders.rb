# frozen_string_literal: true

module LightekCommerce
  class SupplierOrders
    class Invalid < StandardError; end

    MAX_LINES = 50
    MAX_UNITS = 1_000_000
    MAX_UNIT_COST = 1_000_000_000
    MAX_SUBTOTAL = MAX_LINES * MAX_UNITS * MAX_UNIT_COST

    def initialize(order:, actor:)
      @order = order
      @actor = actor
    end

    def save_line!(item_key:, quantity:, unit_cost:)
      unless item_key.to_s.match?(/\A[1-9][0-9]{0,17}(?::[1-9][0-9]{0,17})?\z/)
        raise Invalid, 'Select a tracked physical product or variant.'
      end
      product_id, variant_id = item_key.split(':').map(&:to_i)
      units = amount(quantity, 'Quantity', minimum: 1, maximum: MAX_UNITS)
      cents = amount(unit_cost, 'Unit cost in cents', maximum: MAX_UNIT_COST)
      mutate('draft') do
        product = tracked_products([product_id]).fetch(product_id)
        target = stock_target(product, variant_id)
        line = @order.lines.find_or_initialize_by(product_id: product_id, variant_id: variant_id)
        if line.new_record? && @order.lines.count >= MAX_LINES
          raise Invalid, "A purchase order can contain up to #{MAX_LINES} items."
        end
        name = target.equal?(product) ? product.name : "#{product.name} / #{target.name}"
        line.update!(item_name: name, ordered_quantity: units, unit_cost_cents: cents)
      end
    end

    def remove_line!(line_id:)
      mutate('draft') { @order.lines.find(line_id).destroy! }
    end

    def place!
      mutate('draft') do
        lines = @order.lines.to_a
        raise Invalid, 'Add at least one item before marking the purchase order as ordered.' if lines.empty?

        move_lines!(lines, from: nil, to: 'incoming', units: :ordered_quantity)
        @order.update!(status: 'ordered')
      end
    end

    def receive!(line_id:, quantity:, expected_received:)
      units = amount(quantity, 'Quantity received', minimum: 1, maximum: MAX_UNITS)
      previous = amount(expected_received, 'Previous received count', maximum: MAX_UNITS)
      mutate('ordered') do
        line = @order.lines.find(line_id)
        raise Invalid, 'This line changed. Reload the order and review the received count.' unless line.received_quantity == previous
        raise Invalid, 'The receipt exceeds the outstanding quantity.' if units > line.remaining_quantity

        product = tracked_products([line.product_id]).fetch(line.product_id)
        move!(product, line, from: 'incoming', to: 'available', units: units)
        line.update!(received_quantity: previous + units)
        @order.update!(status: 'received') unless @order.lines.where('received_quantity < ordered_quantity').exists?
      end
    end

    def cancel!
      mutate('draft', 'ordered') do
        if @order.status == 'ordered'
          remaining = @order.lines.where('received_quantity < ordered_quantity').to_a
          move_lines!(remaining, from: 'incoming', to: nil, units: :remaining_quantity)
        end
        @order.update!(status: 'canceled')
      end
    end

    def reconcile_invoice!(reference:, subtotal:)
      name = reference.to_s.strip
      raise Invalid, 'Enter the supplier invoice reference.' if name.blank?
      cents = amount(subtotal, 'Invoice subtotal in cents', maximum: MAX_SUBTOTAL)
      mutate('received', 'canceled') do
        raise Invalid, 'Record received items before reconciling the invoice.' unless @order.lines.where('received_quantity > 0').exists?

        @order.update!(invoice_reference: name, invoice_subtotal_cents: cents)
      end
    end

    private

    def mutate(*statuses)
      @order.with_lock do
        raise Invalid, 'This action is unavailable for the current purchase order status.' unless statuses.include?(@order.status)

        yield
      end
    rescue ActiveRecord::RecordInvalid => error
      raise Invalid, error.record.errors.full_messages.to_sentence
    rescue ActiveRecord::Deadlocked
      raise Invalid, 'Another stock transaction is in progress. Try again.'
    end

    def tracked_products(ids)
      products = Product.where(site_id: @order.site_id, product_type: 'physical', id: ids).order(:id).lock.index_by(&:id)
      raise Invalid, 'One or more purchase order products are no longer available.' unless products.size == ids.uniq.size

      products
    end

    def stock_target(product, variant_id)
      if variant_id
        target = product.variants.where(active: true).lock.find_by(id: variant_id)
        return target if target
      elsif product.track_inventory? && !product.variants.where(active: true).exists?
        return product
      end
      raise Invalid, 'One or more purchase order items no longer have tracked stock.'
    end

    def move_lines!(lines, from:, to:, units:)
      products = tracked_products(lines.map(&:product_id))
      lines.sort_by { |line| [line.product_id, line.variant_id.to_i] }.each do |line|
        move!(products.fetch(line.product_id), line, from: from, to: to, units: line.public_send(units))
      end
    end

    def move!(product, line, from:, to:, units:)
      target = stock_target(product, line.variant_id)
      InventoryStockStates.apply_locked!(product: product, target: target, from: from, to: to, units: units,
        actor: @actor, supplier_order: @order)
    end

    def amount(value, label, maximum:, minimum: 0)
      if value.to_s.match?(/\A(?:0|[1-9][0-9]{0,16})\z/) && value.to_i.between?(minimum, maximum)
        return value.to_i
      end

      raise Invalid, "#{label} must be a whole number from #{minimum} to #{maximum}."
    end
  end
end
