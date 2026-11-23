# frozen_string_literal: true

require "stringio"
require "base64"
require "bigdecimal"

module LightekCommunications
  class AutomaticVoiceFulfillment
    def self.call(add_on)
      new(add_on).call
    end

    def initialize(add_on)
      @add_on = add_on
    end

    def call
      return if @add_on.fulfillment_status.in?(%w[carrier_ready needs_attention])
      return unless @add_on.peer.active? && LightekPeople::LifecycleAccess.active?(@add_on.peer.merchant)

      subscription = @add_on.order.commerce_subscription
      return unless subscription && Fulfillment.billing_receipt(subscription)

      @setup = VoiceSetup.checkout!(@add_on)
      @service = Fulfillment.register_paid_voice!(@add_on)
      @runner = CarrierFulfillment.for_paid_voice(@service, @add_on)
      @carrier = VoipMs.for_paid_voice(@add_on.order_id)
      @selection = @add_on.order.items.sole.purchase_snapshot.fetch("voice_number_request")
      @route = @setup.fetch("destination")
      @add_on.update!(fulfillment_status: "processing")
      if @route["managed"]
        details = ManagedVoiceTrunk.new(@add_on, @carrier).register!(@route)
        @route = @route.merge("sip_account" => details.fetch("account"))
        @pbx = AsteriskVoice.new(@add_on.order_id, details)
      end
      number = @selection.fetch("option") == "port" ? port_number : order_number
      return :waiting_for_carrier unless number

      assign_e911(number)
      @carrier.verify!(account: @route.fetch("sip_account"), phone_number: "+1#{number.did}")
      if @pbx
        Fulfillment.activate_managed_voice!(add_on: @add_on, service: @service, number: number, route: @route, pbx: @pbx)
      else
        @add_on.update!(fulfillment_status: "carrier_ready")
      end
    rescue CarrierFulfillment::Invalid, Fulfillment::Invalid, ActiveRecord::RecordNotFound,
           LightekVault::Service::AccessDenied, LightekVault::Crypto::DecryptionError
      @add_on.update!(fulfillment_status: "needs_attention")
    rescue LightekVault::MasterKey::ConfigurationError
      raise VoipMs::Unavailable, "Voice setup Vault is unavailable."
    end

    private

    def order_number
      prior = confirmed_operation("order_number")
      return prior if prior

      available = @runner.search_numbers!(@selection.fetch("area_code")).find do |row|
        row["did"].start_with?(@selection.fetch("area_code")) &&
          within_budget?(row["perminute_setup"], "max_setup_cents") &&
          within_budget?(row["perminute_monthly"], "max_monthly_cents")
      end
      raise CarrierFulfillment::Invalid, "No number is available within the carrier budget." unless available

      @runner.order_number!(routing.merge(phone_number: "+1#{available.fetch('did')}", billing_type: "1"))
      confirmed_operation("order_number")
    end

    def port_number
      port = confirmed_operation("port_number")
      unless port
        fields = @setup.fetch("port").symbolize_keys.merge(phone_number: @selection.fetch("phone_number"), authorized: "1")
        @runner.port_number!(fields)
        port = confirmed_operation("port_number")
      end

      unless confirmed_operation("port_document")
        @runner.attach_port_file!(StringIO.new(Base64.strict_decode64(@setup.fetch("document"))), authorized: "1")
      end
      @runner.refresh_port!
      if port.reload.carrier_status.to_s.match?(/reject|cancel|denied/i)
        raise CarrierFulfillment::Invalid, "The losing carrier did not complete the transfer."
      end
      unless @carrier.number_on_account?(port.did)
        @add_on.update!(fulfillment_status: "port_pending")
        return
      end
      @runner.route_port!(routing) unless confirmed_operation("route_port")
      port
    end

    def assign_e911(number)
      return if confirmed_operation("provision_e911")

      @runner.provision_e911!(@setup.fetch("emergency").symbolize_keys.merge(routing, phone_number: "+1#{number.did}"))
    end

    def confirmed_operation(name)
      operation = VoiceCarrierOperation.find_by(service: @service, operation: name)
      return unless operation
      return operation if operation.state == "confirmed"

      raise CarrierFulfillment::Invalid, "A previous carrier write requires review."
    end

    def routing
      { sip_account: @route.fetch("sip_account"), pop: @route.fetch("pop").to_s, authorized: "1" }
    end

    def within_budget?(value, ceiling)
      price = BigDecimal(value.to_s, exception: false)
      price&.finite? && price >= 0 && price * 100 <= @route.fetch(ceiling)
    end
  end
end
