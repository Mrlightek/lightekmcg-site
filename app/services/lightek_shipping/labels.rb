require "base64"
require "stringio"
module LightekShipping
  class Labels
    def self.issue!(quote:)
      raise ArgumentError, "Remote labels are purchased through the shipping network" if quote.broker_reference.present?
      order = quote.purchase_order
      raise ArgumentError, "Confirmed shipping payment is required" unless order&.paid_at? && %w[paid fulfilled].include?(order.status) &&
        ((order.purpose == "shipping_label" && order.subtotal_cents >= quote.platform_price_cents) || (order.shipping_quote_id == quote.id && order.shipping_cents >= quote.platform_price_cents))
      shipment = nil
      quote.with_lock { shipment = Shipment.find_or_create_by!(quote: quote) }
      shipment.with_lock do
        return shipment if %w[ready submitting review canceled].include?(shipment.status)
        shipment.update!(status: "submitting", submitted_at: Time.current, error_message: nil)
      end
      account = Account.find_by!(provider: "fedex", enabled: true)
      raise ArgumentError, "Shipping environment changed; review the original quote" unless account.sandbox? == quote.sandbox?
      stripe_test = DymondBank::StripeCredentials.secret_key.to_s.match?(/\A(?:sk|rk)_test_/)
      raise ArgumentError, "Shipping payment environment differs from the carrier account" unless quote.sandbox? == stripe_test
      payload = quote.shipment_payload.deep_dup.merge("serviceType" => quote.service_code, "shipDateStamp" => Date.current.iso8601)
      response = Fedex.new(account: account).ship(payload, reference: shipment.public_key)
      result = response.fetch("output").fetch("transactionShipments").sole
      pieces = result.fetch("pieceResponses")
      documents = pieces.flat_map { |piece| Array(piece["packageDocuments"]) }.select { |document| document["contentType"] == "LABEL" || document["docType"] == "PDF" }
      raise ArgumentError, "Carrier did not return a PDF label" if documents.empty?
      documents.each_with_index do |document, index|
        bytes = Base64.strict_decode64(document.fetch("encodedLabel"))
        raise ArgumentError, "Invalid label document" unless bytes.start_with?("%PDF-") && bytes.bytesize <= 5.megabytes
        shipment.labels.attach(io: StringIO.new(bytes), filename: "shipping-#{shipment.public_key}-#{index + 1}.pdf", content_type: "application/pdf")
      end
      tracking = result["masterTrackingNumber"].presence || pieces.first.fetch("trackingNumber")
      cost = result.dig("completedShipmentDetail", "shipmentRating", "shipmentRateDetails")&.first&.fetch("totalNetCharge", nil)
      cost = cost["amount"] if cost.is_a?(Hash)
      shipment.update!(status: "ready", tracking_number: tracking, completed_at: Time.current,
        actual_carrier_cost_cents: cost ? (BigDecimal(cost.to_s) * 100).ceil : nil)
      LightekCommerce::Fulfillment.complete!(order: order, reference: tracking) if order.status == "paid"
      shipment
    rescue StandardError => error
      # FedEx transaction references are not a promise of idempotent billing.
      # An uncertain result must never automatically purchase a second label.
      shipment&.update!(status: "review", error_message: "Carrier confirmation needs review (#{error.class}); do not purchase another label for this quote.") if shipment&.status == "submitting"
      raise
    end
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
      data = Fedex.new(account: Account.find_by!(provider: "fedex", enabled: true)).track(shipment.tracking_number)
      result = Array(data.dig("output", "completeTrackResults")).first.to_h.fetch("trackResults", []).first.to_h
      shipment.update!(carrier_status: result.dig("latestStatusDetail", "description"))
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
        response = Fedex.new(account: Account.find_by!(provider: "fedex", enabled: true)).cancel(shipment.tracking_number)
        raise ArgumentError, "FedEx did not confirm cancellation" unless response.dig("output", "cancelledShipment") == true
        shipment.update!(status: "canceled")
      end
      shipment
    end
  end
end
