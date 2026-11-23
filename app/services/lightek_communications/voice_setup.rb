# frozen_string_literal: true

require "json"
require "base64"

module LightekCommunications
  class VoiceSetup
    class Invalid < StandardError; end

    PURPOSE = "paid_voice_setup"
    ADDRESS_FIELDS = %i[full_name street_number street_name address_type address_number city state zip].freeze
    PORT_FIELDS = (CarrierFulfillment::PORT_FIELDS + %i[isPartial address2 pin]).freeze

    def self.route(peer)
      managed = ManagedVoiceTrunk.destination
      return managed if managed

      routes = JSON.parse(ENV.fetch("LIGHTEK_VOICE_PBX_ROUTES", "{}"))
      entry = routes.is_a?(Hash) && routes[peer.site.host]
      return unless entry.is_a?(Hash) && VoipMs::SIP_ACCOUNT.match?(entry["sip_account"].to_s)
      return unless %w[pop max_setup_cents max_monthly_cents].all? do |key|
        entry[key].is_a?(Integer) && entry[key].between?(0, 1_000_000)
      end
      return unless entry["pop"].positive? && entry["max_monthly_cents"].positive?

      entry.slice("sip_account", "pop", "max_setup_cents", "max_monthly_cents")
    rescue JSON::ParserError
      nil
    end

    def self.store!(peer: nil, order:, selection:, fields:, buyer: nil)
      destination = peer ? route(peer) : ManagedVoiceTrunk.destination
      raise Invalid, "Phone service is unavailable for this installation." unless destination && (peer || buyer)
      raise Invalid, "Confirm the emergency service address." unless fields["confirm_emergency_address"] == "1"

      address = fields["emergency"].to_h.slice(*ADDRESS_FIELDS.map(&:to_s))
      required!(address, CarrierFulfillment::E911_FIELDS)
      unless address["street_number"].match?(/\A[1-9][0-9]{0,11}\z/) && address["state"].match?(/\A[A-Za-z]{2}\z/) &&
          address["zip"].match?(/\A[0-9]{5}(?:-[0-9]{4})?\z/)
        raise Invalid, "Enter a numeric street number, two-letter US state and ZIP code."
      end
      if address["address_type"].present? || address["address_number"].present?
        unless address["address_type"].to_s.match?(/\A[A-Za-z]{1,20}\z/) && address["address_number"].to_s.match?(/\A[1-9][0-9]{0,11}\z/)
          raise Invalid, "Enter a unit type and numeric unit number."
        end
      end

      payload = { "destination" => destination, "emergency" => address }
      if selection["option"] == "port"
        raise Invalid, "Confirm you are authorized to transfer this number." unless fields["authorize_port"] == "1"
        port = fields["port"].to_h.slice(*PORT_FIELDS.map(&:to_s))
        required!(port, CarrierFulfillment::PORT_FIELDS)
        raise Invalid, "Choose whether other lines are staying with your current carrier." unless port["isPartial"].in?(%w[0 1])

        document = fields["document"].to_s
        raise Invalid, "Upload your current carrier invoice as a PDF of up to 2 MB." if document.bytesize > 2_796_208
        begin
          decoded = Base64.strict_decode64(document)
        rescue ArgumentError
          decoded = ""
        end
        unless decoded.start_with?("%PDF-") && decoded.bytesize <= 2.megabytes
          raise Invalid, "Upload your current carrier invoice as a PDF of up to 2 MB."
        end
        payload.merge!("port" => port, "document" => document)
      end

      slug = "voice-setup-order-#{order.id}"
      LightekVault::Service.store!(name: "Voice setup order ##{order.id}", slug: slug, payload: payload,
        purpose: PURPOSE, access_policy: { "consumers" => [name], "purposes" => [PURPOSE] },
        requested_by: peer ? "voice-checkout:#{peer.id}" : "full-package-checkout:#{buyer.id}")
      slug
    rescue LightekVault::MasterKey::ConfigurationError
      raise Invalid, "Phone service setup is temporarily unavailable."
    end

    def self.checkout!(add_on)
      LightekVault::Service.checkout!(slug: add_on.setup_secret_slug, consumer: name, purpose: PURPOSE,
        requested_by: "voice-fulfillment:#{add_on.order_id}")
    end

    def self.required!(data, fields)
      fields.each do |field|
        value = data[field.to_s].to_s.strip
        if value.blank? || value.length > 140 || value.match?(/[[:cntrl:]]/)
          raise Invalid, "Complete the required setup fields."
        end
        data[field.to_s] = value
      end
    end
    private_class_method :required!
  end
end
