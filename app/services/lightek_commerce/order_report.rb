# frozen_string_literal: true

require 'csv'
require 'date'

module LightekCommerce
  class OrderReport
    class Invalid < StandardError; end

    FILTERS = %i[status from through lookup].freeze
    MAX_ORDERS = 5_000
    MAX_ITEMS = 50_000
    ORDER_COLUMNS = %w[order_id created_at_utc paid_at_utc fulfilled_at_utc status purpose buyer_email currency merchandise_cents merchandise_discount_cents shipping_cents shipping_discount_cents tax_cents checkout_fee_cents gift_card_tender_cents total_cents refunded_cents].freeze
    ITEM_COLUMNS = %w[order_id line_item_id product_id variant_id item_name quantity unit_price_cents gross_line_cents merchandise_discount_cents].freeze

    def initialize(site:, filters:)
      @orders = Order.visible.where(site: site)
      status = filters[:status].to_s.presence
      unless status.nil? || Order::STATUSES.include?(status)
        raise Invalid, 'Choose a valid order status.'
      end
      @orders = @orders.where(status: status) if status

      from = parse_date(filters[:from])
      through = parse_date(filters[:through])
      raise Invalid, 'The end date must be on or after the start date.' if from && through && from > through

      @orders = @orders.where(created_at: from.in_time_zone.beginning_of_day..) if from
      @orders = @orders.where(created_at: ...(through + 1.day).in_time_zone.beginning_of_day) if through

      lookup = filters[:lookup].to_s.strip
      if lookup.match?(/\A#?[1-9][0-9]{0,17}\z/)
        @orders = @orders.where(id: lookup.delete_prefix('#').to_i)
      elsif lookup.present?
        unless lookup.length <= 254 && URI::MailTo::EMAIL_REGEXP.match?(lookup)
          raise Invalid, 'Enter an order number or a complete buyer email.'
        end
        @orders = @orders.where('LOWER(customer_email) = ?', lookup.downcase)
      end
    end

    def recent
      @orders.includes(items: :product).order(created_at: :desc, id: :desc).limit(150)
    end

    def csv(kind)
      raise Invalid, 'Choose an order or line-item export.' unless %w[orders items].include?(kind)

      ids = @orders.order(:id).limit(MAX_ORDERS + 1).pluck(:id)
      raise Invalid, "Narrow this export to #{MAX_ORDERS} orders." if ids.length > MAX_ORDERS

      CSV.generate do |output|
        if kind == 'orders'
          output << ORDER_COLUMNS
          @orders.where(id: ids).find_each { |order| output << order_row(order) }
        else
          items = OrderItem.joins(:order).merge(@orders.where(id: ids))
          raise Invalid, "Narrow this export to #{MAX_ITEMS} line items." if items.limit(MAX_ITEMS + 1).count > MAX_ITEMS

          output << ITEM_COLUMNS
          items.find_each { |item| output << item_row(item) }
        end
      end
    end

    private

    def parse_date(value)
      return if value.blank?

      raise Invalid, 'Enter dates in YYYY-MM-DD format.' unless value.to_s.match?(/\A[1-9][0-9]{3}-[0-9]{2}-[0-9]{2}\z/)

      Date.iso8601(value.to_s)
    rescue Date::Error
      raise Invalid, 'Enter a valid calendar date.'
    end

    def order_row(order)
      [order.id, order.created_at.utc.iso8601, order.paid_at&.utc&.iso8601, order.fulfilled_at&.utc&.iso8601, order.status,
        spreadsheet_text(order.purpose), spreadsheet_text(order.customer_email), order.currency, order.subtotal_cents, order.discount_amount,
        order.shipping_cents, order.shipping_discount_amount, order.tax_cents, order.buyer_fee_cents, order.gift_applied,
        order.total_cents, order.refunded_cents]
    end

    def item_row(item)
      [item.order_id, item.id, item.product_id, item.variant_id, spreadsheet_text(item.name), item.quantity, item.unit_price_cents,
        item.line_total_cents, item.purchase_snapshot.to_h['merchandise_discount_cents']]
    end

    def spreadsheet_text(value)
      return value unless value.to_s.match?(/\A(?:[[:space:]]*[=+@-]|[\t\r\n])/)

      "'#{value}"
    end
  end
end
