# frozen_string_literal: true

require 'base64'

module LightekCommerce
  class ReturnShipping
    class Invalid < StandardError; end

    FORMATS = {'application/pdf' => 'pdf', 'image/gif' => 'gif'}.freeze

    def self.available?(order)
      quote = order.shipping_quote
      quote && quote.site_id == order.site_id &&
        quote.shipment_payload.is_a?(Hash) &&
        quote.shipment_payload['shipper'].present? && quote.shipment_payload['recipients'].is_a?(Array) &&
        quote.shipment_payload['recipients'].one?
    end

    def self.rates!(order:, return_id:, package:)
      raise Invalid, 'This order has no original shipping address for a carrier return label.' unless available?(order)

      record = MerchandiseReturn.where(order_id: order.id, status: 'approved').find(return_id)
      raise Invalid, 'A label purchase is already linked to this return.' if record.return_shipping_quote_id?
      raise Invalid, 'A return label has already been uploaded.' if ReturnLabel.exists?(merchandise_return_id: record.id)

      outbound = order.shipping_quote.shipment_payload
      LightekShipping::Quotes.create!(site: order.site, origin: address(outbound.fetch('recipients').sole),
        recipient: address(outbound.fetch('shipper')), packages: [package], merchandise_return: record)
    end

    def self.purchase!(order:, return_id:, quote_key:, email:, return_url:)
      quote = order.with_lock do
        record = MerchandiseReturn.where(order_id: order.id, status: 'approved').find(return_id)
        raise Invalid, 'A return label has already been uploaded.' if ReturnLabel.exists?(merchandise_return_id: record.id)

        selected = quotes_for(order).where(merchandise_return_id: record.id).find_by!(public_key: quote_key)
        if record.return_shipping_quote_id? && record.return_shipping_quote_id != selected.id
          raise Invalid, 'A different label purchase is already linked to this return.'
        end
        if !record.return_shipping_quote_id? && selected.expires_at <= Time.current
          raise Invalid, 'Request new carrier rates before purchasing.'
        end

        record.update!(return_shipping_quote_id: selected.id)
        selected
      end

      LightekShipping::Purchases.start!(quote: quote, email: email, return_url: return_url)
    end

    def self.refresh!(order:, return_id:)
      LightekShipping::Labels.refresh!(quote: selected_quote!(order, return_id))
    end

    def self.label!(order:, return_id:)
      quote = selected_quote!(order, return_id)
      raise ActiveRecord::RecordNotFound unless quote.shipment&.status == 'ready'

      if quote.broker_reference.present?
        client = LightekReservations::Federation::Client.new(order.site)
        result = client.request("shipping/quotes/#{quote.broker_reference}/labels/0")
        content_type = result.fetch('content_type')
        bytes = Base64.strict_decode64(result.fetch('data'))
      else
        file = quote.shipment.labels.attachments.order(:id).first!
        content_type = file.content_type
        bytes = file.download
      end
      extension = FORMATS[content_type]
      raise Invalid, 'The carrier returned an unsupported label format.' unless extension

      [bytes, content_type, extension]
    end

    def self.selected_quote!(order, return_id)
      record = MerchandiseReturn.where(order_id: order.id, status: ReturnLabel::VISIBLE_STATUSES).find(return_id)
      quotes_for(order).find_by!(id: record.return_shipping_quote_id, merchandise_return_id: record.id)
    end

    def self.quotes_for(order)
      LightekShipping::Quote.where(site_id: order.site_id)
    end

    def self.address(party)
      contact = party.fetch('contact')
      fields = party.fetch('address')
      {'name' => contact.fetch('personName'), 'phone' => contact.fetch('phoneNumber'), 'street' => fields.fetch('streetLines').first,
       'city' => fields.fetch('city'), 'state' => fields.fetch('stateOrProvinceCode'), 'postal_code' => fields.fetch('postalCode'),
       'country' => fields.fetch('countryCode'), 'residential' => fields.fetch('residential', true)}
    rescue KeyError, TypeError
      raise Invalid, 'The outbound shipment does not have a complete shipping address.'
    end
    private_class_method :address, :selected_quote!, :quotes_for
  end
end
