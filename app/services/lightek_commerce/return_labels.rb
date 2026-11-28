# frozen_string_literal: true

module LightekCommerce
  class ReturnLabels
    class Invalid < StandardError; end

    def self.upload!(order:, return_id:, actor:, upload:, carrier:, tracking_number:)
      raise ActiveRecord::RecordNotFound unless return_id.to_s.match?(/\A[1-9][0-9]{0,17}\z/)

      unless upload.is_a?(ActionDispatch::Http::UploadedFile)
        raise Invalid, 'Choose a PDF return label.'
      end

      pdf = upload.read(ReturnLabel::MAX_BYTES + 1)
      unless pdf && pdf.bytesize <= ReturnLabel::MAX_BYTES && pdf.start_with?('%PDF-') && pdf.rstrip.end_with?('%%EOF')
        raise Invalid, 'Choose a PDF return label up to 512 KB.'
      end
      carrier = carrier.to_s.strip.presence
      tracking_number = tracking_number.to_s.strip.upcase.presence
      if (carrier || tracking_number) && !LightekShipping::Quote.carrier_tracking_url(carrier, tracking_number)
        raise Invalid, 'Choose UPS or FedEx and enter a valid tracking number, or leave both blank.'
      end

      order.with_lock do
        record = MerchandiseReturn.where(order_id: order.id).find(return_id)
        raise Invalid, 'Approve the return before adding a label.' unless record.status == 'approved'
        raise Invalid, 'A carrier label purchase is already linked to this return.' if record.return_shipping_quote_id?

        label = ReturnLabel.find_or_initialize_by(merchandise_return_id: record.id)
        label.update!(pdf: pdf, carrier: carrier, tracking_number: tracking_number, uploaded_by_id: actor.id)
      end
    rescue ActiveRecord::RecordInvalid => error
      raise Invalid, error.record.errors.full_messages.to_sentence
    end

    def self.download!(order:, return_id:)
      raise ActiveRecord::RecordNotFound unless return_id.to_s.match?(/\A[1-9][0-9]{0,17}\z/)

      eligible = MerchandiseReturn.where(id: return_id, order_id: order.id, status: ReturnLabel::VISIBLE_STATUSES)
      ReturnLabel.find_by!(merchandise_return_id: eligible.select(:id)).pdf
    end
  end
end
