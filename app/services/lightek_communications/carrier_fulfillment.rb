# frozen_string_literal: true

require "base64"

module LightekCommunications
  class CarrierFulfillment
    class Invalid < StandardError; end

    NUMBER_ACTIONS = %w[order_number port_number].freeze
    PORT_FIELDS = %i[statementName firstName lastName address1 city state zip providerName providerAccount].freeze
    E911_FIELDS = %i[full_name street_number street_name city state zip].freeze

    def initialize(service, operator, connection: nil)
      Fulfillment.check_operator!(operator) unless connection
      @service = service
      @operator = operator
      @carrier = connection
    end

    def self.for_paid_voice(service, add_on)
      unless add_on.setup_secret_slug.present? && service.subscription.order_id == add_on.order_id &&
          service.kind == "voice" && Fulfillment.billing_receipt(service.subscription)
        raise Invalid, "The paid Voice order could not be verified."
      end

      new(service, nil, connection: VoipMs.for_paid_voice(add_on.order_id))
    end

    def search_numbers!(area_code)
      raise Invalid, "Enter a three-digit area code." unless area_code.to_s.match?(/\A[2-9][0-9]{2}\z/)

      carrier.search_numbers!(area_code: area_code)
    end

    def order_number!(fields)
      did = number!(fields)
      account, pop = route_fields!(fields)
      rate = positive_integer!(fields[:billing_type], "carrier rate")
      raise Invalid, "Choose a carrier rate." unless rate.in?([1, 2])

      submit!("order_number", did, fields) do
        carrier.order_number!(did: did, routing: "account:#{account}", pop: pop, billing_type: rate)
        { carrier_reference: did }
      end
    end

    def port_number!(fields)
      did = number!(fields)
      data = required_fields!(fields, PORT_FIELDS)
      raise Invalid, "Choose whether this is a partial port." unless fields[:isPartial].in?(%w[0 1])
      data[:locationType] = 1
      data[:isPartial] = fields.fetch(:isPartial)
      data[:address2] = fields[:address2].to_s.strip.first(140) if fields[:address2].present?
      data[:pin] = fields[:pin].to_s.strip.first(40) if fields[:pin].present?

      preflight = -> { carrier.verify_portability!(did) }
      submit!("port_number", did, fields, preflight: preflight) do
        receipt = carrier.port_number!(did: did, fields: data)
        port = positive_integer!(receipt["port"], "carrier port reference")
        { carrier_reference: port.to_s, carrier_status: "Submitted" }
      end
    end

    def refresh_port!
      port = confirmed_port!
      result = carrier.port_status!(port.carrier_reference)
      status = result["post_status_description"].presence || result["post_status"].presence
      raise Invalid, "VoIP.ms did not return a port status." unless status

      port.update!(carrier_status: status.to_s.first(140))
    end

    def attach_port_file!(file, fields)
      port = confirmed_port!
      raise Invalid, "Choose a PDF of up to 2 MB." unless file.respond_to?(:read) && file.respond_to?(:size) &&
        file.size.between?(1, 2.megabytes)
      bytes = file.read(2.megabytes + 1)
      raise Invalid, "Choose a PDF of up to 2 MB." unless bytes&.start_with?("%PDF-") && bytes.bytesize <= 2.megabytes

      submit!("port_document", port.did, fields) do
        carrier.attach_port_file!(port.carrier_reference, Base64.strict_encode64(bytes))
        { carrier_reference: port.carrier_reference }
      end
    end

    def route_port!(fields)
      port = confirmed_port!
      account, pop = route_fields!(fields)
      submit!("route_port", port.did, fields) do
        carrier.route_port!(did: port.did, account: account, pop: pop)
        { carrier_reference: port.carrier_reference }
      end
    end

    def provision_e911!(fields)
      assignment = VoiceCarrierOperation.find_by(service: @service, operation: NUMBER_ACTIONS, state: "confirmed")
      raise Invalid, "Order or port a number for this service first." unless assignment

      account = sip_account!(fields)
      address = required_fields!(fields, E911_FIELDS)
      address[:street_number] = positive_integer!(address[:street_number], "street number")
      address[:state] = address[:state].upcase
      unless address[:state].match?(/\A[A-Z]{2}\z/) && address[:zip].match?(/\A[0-9]{5}(?:-[0-9]{4})?\z/)
        raise Invalid, "Enter a two-letter US state and ZIP code."
      end
      if fields[:address_type].present? || fields[:address_number].present?
        address[:address_type] = fields[:address_type].to_s.strip
        raise Invalid, "Enter a valid unit type." unless address[:address_type].match?(/\A[A-Za-z]{1,20}\z/)
        address[:address_number] = positive_integer!(fields[:address_number], "unit number")
      end

      preflight = -> { carrier.validate_e911!(did: assignment.did, account: account, fields: address) }
      submit!("provision_e911", assignment.did, fields, preflight: preflight) do
        carrier.provision_e911!(did: assignment.did, fields: address)
        { carrier_reference: assignment.did }
      end
    end

    private

    def submit!(operation, did, fields, preflight: nil)
      raise Invalid, "Confirm this carrier request before submitting." unless fields[:authorized] == "1"

      require_paid_voice!
      verify_number_request!(operation, did) if NUMBER_ACTIONS.include?(operation)
      carrier
      preflight&.call
      receipt = @service.with_lock do
        require_paid_voice!
        verify_number_request!(operation, did) if NUMBER_ACTIONS.include?(operation)
        if NUMBER_ACTIONS.include?(operation) &&
            (@service.status != "provisioning" || VoiceCarrierOperation.exists?(service: @service, operation: NUMBER_ACTIONS))
          raise Invalid, "Only a new Voice service without a number request can order or port a number."
        end
        if VoiceCarrierOperation.exists?(service: @service, operation: operation)
          raise Invalid, "This carrier action has already been submitted. Review its status before repeating it."
        end

        VoiceCarrierOperation.create!(service: @service, operator: @operator, operation: operation, did: did)
      end
      result = yield
      receipt.update!(state: "confirmed", **result)
    rescue ActiveRecord::RecordNotUnique
      raise Invalid, "This action or phone number already belongs to a recorded request."
    rescue VoipMs::Unavailable, Invalid
      if receipt
        receipt.update!(state: "review")
        raise Invalid, "VoIP.ms did not confirm this request. Review the carrier account before trying again."
      end
      raise
    end

    def verify_number_request!(operation, did)
      request = @service.subscription.order.items.sole.purchase_snapshot["voice_number_request"]
      return unless request
      return if request["option"] == "new" && operation == "order_number" && did.start_with?(request.fetch("area_code"))
      return if request["option"] == "port" && operation == "port_number" && "+1#{did}" == request["phone_number"]

      raise Invalid, "Use the number option and number or area code the customer selected at checkout."
    end

    def require_paid_voice!
      raise Invalid, "This action needs a paid Voice service." unless @service.kind == "voice" &&
        Fulfillment.billing_receipt(@service.subscription.reload)
    end

    def carrier = @carrier ||= VoipMs.for_operator(@operator)

    def confirmed_port!
      VoiceCarrierOperation.find_by(service: @service, operation: "port_number", state: "confirmed") ||
        raise(Invalid, "Submit and confirm a port request before continuing.")
    end

    def number!(fields)
      value = fields[:phone_number].to_s.strip
      raise Invalid, "Enter a North American number in +1 format." unless VoipMs::NANP_NUMBER.match?(value)
      value.delete_prefix("+1")
    end

    def sip_account!(fields)
      value = fields[:sip_account].to_s.strip
      raise Invalid, "Enter a valid SIP subaccount." unless VoipMs::SIP_ACCOUNT.match?(value)
      value
    end

    def route_fields!(fields)
      [sip_account!(fields), positive_integer!(fields[:pop], "VoIP.ms PoP ID")]
    end

    def positive_integer!(value, label)
      raise Invalid, "Enter a valid #{label}." unless value.to_s.match?(/\A[1-9][0-9]{0,11}\z/)
      value.to_i
    end

    def required_fields!(fields, keys)
      values = keys.to_h { |key| [key, fields[key].to_s.strip] }
      if values.values.any? { |value| value.blank? || value.length > 140 || value.match?(/[[:cntrl:]]/) }
        raise Invalid, "Complete all carrier fields."
      end
      values
    end
  end
end
