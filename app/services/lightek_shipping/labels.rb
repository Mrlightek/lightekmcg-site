require "base64"
require "stringio"
module LightekShipping
  class Labels
    def self.issue!(quote:)
      raise ArgumentError, "Remote labels are purchased through the shipping network" if quote.broker_reference.present?
      order = quote.purchase_order
      raise ArgumentError, "Confirmed shipping payment is required" unless order&.paid_at? && %w[paid fulfilled].include?(order.status) && funded?(order, quote)
      shipment = nil
      quote.with_lock { shipment = Shipment.find_or_create_by!(quote: quote) }
      shipment.with_lock do
        return shipment if %w[ready submitting review canceled].include?(shipment.status)
        shipment.update!(status: "submitting", submitted_at: Time.current, error_message: nil)
      end
      account = Account.find_by!(provider: quote.provider, enabled: true)
      raise ArgumentError, "Shipping environment changed; review the original quote" unless account.sandbox? == quote.sandbox?
      stripe_test = DymondBank::StripeCredentials.secret_key.to_s.match?(/\A(?:sk|rk)_test_/)
      raise ArgumentError, "Shipping payment environment differs from the carrier account" unless quote.sandbox? == stripe_test
      payload = quote.shipment_payload.deep_dup.merge("serviceType" => quote.service_code, "shipDateStamp" => Date.current.iso8601)
      response = account.carrier_class.new(account: account).ship(payload, reference: shipment.public_key)
      label = quote.provider == 'ups' ? response : fedex_label(response)
      documents = label.fetch(:documents)
      raise ArgumentError, 'Carrier did not return every package label' unless documents.size == payload.fetch('totalPackageCount')

      extension, content_type, header = quote.provider == 'ups' ? ['gif', 'image/gif', 'GIF8'] : ['pdf', 'application/pdf', '%PDF-']
      decoded = documents.map do |data|
        bytes = Base64.strict_decode64(data)
        raise ArgumentError, 'Invalid label document' unless bytes.start_with?(header) && bytes.bytesize <= 5.megabytes

        bytes
      end
      decoded.each_with_index do |bytes, index|
        shipment.labels.attach(io: StringIO.new(bytes), filename: "shipping-#{shipment.public_key}-#{index + 1}.#{extension}", content_type: content_type)
      end
      tracking = label.fetch(:tracking_number)
      shipment.update!(status: "ready", tracking_number: tracking, completed_at: Time.current, actual_carrier_cost_cents: label[:cost_cents])
      LightekCommerce::Fulfillment.complete!(order: order, reference: tracking) if order.status == "paid"
      shipment
    rescue StandardError => error
      # FedEx transaction references are not a promise of idempotent billing.
      # An uncertain result must never automatically purchase a second label.
      shipment&.update!(status: "review", error_message: "Carrier confirmation needs review (#{error.class}); do not purchase another label for this quote.") if shipment&.status == "submitting"
      raise
    end
    def self.fedex_label(response)
      result = response.fetch("output").fetch("transactionShipments").sole
      pieces = result.fetch("pieceResponses")
      documents = pieces.flat_map do |piece|
        Array(piece["packageDocuments"]).filter_map do |document|
          document['encodedLabel'] if document['contentType'] == 'LABEL' || document['docType'] == 'PDF'
        end
      end
      cost = result.dig("completedShipmentDetail", "shipmentRating", "shipmentRateDetails")&.first&.fetch("totalNetCharge", nil)
      cost = cost["amount"] if cost.is_a?(Hash)
      {documents: documents, tracking_number: result["masterTrackingNumber"].presence || pieces.first.fetch("trackingNumber"),
        cost_cents: cost ? (BigDecimal(cost.to_s) * 100).ceil : nil}
    end
    private_class_method :fedex_label

    def self.funded?(order, quote)
      return order.subtotal_cents >= quote.platform_price_cents if order.purpose == 'shipping_label'
      return false unless order.shipping_quote_id == quote.id
      return true if order.shipping_cents >= quote.platform_price_cents
      return false unless order.shipping_discount_amount.positive? && order.shipping_cents == order.quoted_shipping_charge_cents

      LightekCommerce::MerchantPayouts.fee_quote(order)
      true
    rescue LightekCommerce::MerchantPayouts::Invalid, LightekCommerce::RevenueSharing::Invalid
      false
    end
    private_class_method :funded?

    def self.refresh!(quote:)
      if quote.broker_reference.present?
        data = LightekReservations::Federation::Client.new(quote.site).request("shipping/quotes/#{quote.broker_reference}/status")
        shipment = Shipment.find_or_initialize_by(quote: quote)
        shipment.assign_attributes(status: data.fetch("status"), tracking_number: data["tracking_number"], carrier_status: data["carrier_status"])
        shipment.save!
        return shipment
      end
      shipment = quote.shipment
      if !shipment && quote.purchase_order&.paid_at?
        LabelJob.perform_later(quote.purchase_order_id)
      end
      return shipment unless shipment&.tracking_number.present? && shipment.status == "ready"
      account = Account.find_by!(provider: quote.provider, enabled: true)
      raise ArgumentError, 'Shipping environment changed; review the original quote' unless account.sandbox? == quote.sandbox?

      data = account.carrier_class.new(account: account).track(shipment.tracking_number)
      status = quote.provider == 'ups' ? data : data.dig("output", "completeTrackResults", 0, "trackResults", 0, "latestStatusDetail", "description")
      shipment.update!(carrier_status: status) if status.present?
      shipment
    end
    def self.cancel!(quote:)
      if quote.broker_reference.present?
        LightekReservations::Federation::Client.new(quote.site).request("shipping/quotes/#{quote.broker_reference}/cancel", method: :post)
        return refresh!(quote: quote)
      end
      shipment = quote.shipment || raise(ArgumentError, "No shipment exists")
      shipment.with_lock do
        return shipment if shipment.status == "canceled"
        raise ArgumentError, "Only confirmed labels can be canceled" unless shipment.status == "ready"
        account = Account.find_by!(provider: quote.provider, enabled: true)
        raise ArgumentError, 'Shipping environment changed; review the original quote' unless account.sandbox? == quote.sandbox?

        response = account.carrier_class.new(account: account).cancel(shipment.tracking_number)
        confirmed = quote.provider == 'ups' ? response : response.dig('output', 'cancelledShipment')
        raise ArgumentError, 'The carrier did not confirm cancellation' unless confirmed == true
        shipment.update!(status: "canceled")
      end
      shipment
    end
  end
end
