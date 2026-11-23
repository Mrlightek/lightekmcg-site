# frozen_string_literal: true

module LightekCommunications
  class Fulfillment
    class Invalid < StandardError; end

    TEST_EVIDENCE = {
      "internet" => {
        access_reference: "Access connection reference",
        gateway_reference: "Gateway subscriber reference",
        traffic_test_reference: "Upstream traffic test reference"
      }.freeze,
      "voice" => {
        carrier_reference: "Carrier activation reference",
        sip_account: "VoIP.ms SIP subaccount",
        phone_number: "Public phone number (E.164)",
        inbound_test_reference: "Inbound call test reference",
        outbound_test_reference: "Outbound call test reference",
        emergency_test_reference: "Carrier emergency calling test reference"
      }.freeze
    }.freeze

    TRANSITIONS = {
      "activate" => %w[provisioning in_service].freeze,
      "suspend" => %w[in_service suspended].freeze,
      "restore" => %w[suspended in_service].freeze
    }.freeze

    def self.billing_receipt(subscription, now: Time.current)
      order = subscription.order
      return unless subscription.status == "active" && order.status.in?(%w[paid fulfilled]) && order.paid_at?
      return unless subscription.current_period_start && subscription.current_period_end
      return unless subscription.current_period_start <= now && subscription.current_period_end > now

      subscription.billing_invoices.where(currency: subscription.currency)
        .where(paid_at: subscription.current_period_start..now)
        .where("amount_paid_cents >= ?", subscription.amount_cents)
        .joins(:settlement_order)
        .where(lightek_commerce_orders: { status: %w[paid fulfilled] })
        .order(paid_at: :desc, id: :desc).first
    end

    def self.register!(order:, operator:)
      check_operator!(operator)
      order.with_lock do
        subscription = order.commerce_subscription
        kind = order_kind(order)
        raise Invalid, "Select a Lightek Voice or Internet subscription order." unless subscription && kind

        subscription.with_lock do
          existing = Service.find_by(subscription: subscription)
          next existing if existing

          receipt = billing_receipt(subscription)
          raise Invalid, "This order needs a current paid subscription receipt." unless receipt

          Service.create!(subscription: subscription, kind: kind).tap do |service|
            service.events.create!(operator: operator, action: "register", billing_invoice: receipt)
          end
        end
      end
    end

    def self.transition!(service:, action:, operator:, evidence:)
      check_operator!(operator)
      transition = TRANSITIONS[action]
      raise Invalid, "Choose an available provisioning action." unless transition

      raise Invalid, "This service changed. Reload and check its current status." unless service.status == transition.first

      proof = validated_evidence(service.kind, action, evidence)
      if service.kind == "voice" && action != "suspend"
        require_carrier_completion!(service, proof)
        proof.merge!(VoipMs.verify!(operator: operator, account: proof.fetch(:sip_account), phone_number: proof.fetch(:phone_number)))
      end

      subscription = service.subscription
      subscription.order.with_lock do
        subscription.with_lock do
          service.with_lock do
            from, to = transition
            raise Invalid, "This service changed. Reload and check its current status." unless service.status == from

            receipt = billing_receipt(subscription) unless action == "suspend"
            raise Invalid, "Activation needs a current paid subscription receipt." if action != "suspend" && !receipt

            require_carrier_completion!(service, proof) if service.kind == "voice" && action != "suspend"
            service.events.create!(operator: operator, action: action, billing_invoice: receipt,
              evidence: proof)
            service.update!(status: to)
          end
        end
      end
    end

    def self.require_carrier_completion!(service, proof)
      request = VoiceCarrierOperation.find_by(service: service, operation: CarrierFulfillment::NUMBER_ACTIONS)
      return unless request
      return if request.state == "confirmed" && proof.fetch(:phone_number) == "+1#{request.did}" &&
        VoiceCarrierOperation.exists?(service: service, operation: "provision_e911", did: request.did, state: "confirmed")

      raise Invalid, "Finish the carrier number and E911 steps for this phone number before activation."
    end
    private_class_method :require_carrier_completion!

    def self.order_kind(order)
      return unless order.purpose == "purchase" && order.site.tenant&.role == "super_admin"

      item = order.items.sole
      return unless item.quantity == 1

      snapshot = item.purchase_snapshot.to_h
      return unless snapshot["product_type"] == "service" && snapshot["billing_interval"].in?(%w[month year])

      snapshot["communications_kind"].presence_in(LightekCommerce::Product::COMMUNICATIONS_SLUGS.values)
    rescue ActiveRecord::RecordNotFound, ActiveRecord::SoleRecordExceeded
      nil
    end

    def self.validated_evidence(kind, action, evidence)
      fields = action == "suspend" ? { suspension_reference: "Access or carrier suspension reference" } : TEST_EVIDENCE.fetch(kind)
      fields.to_h do |key, label|
        value = evidence[key].to_s.strip
        format = key == :phone_number ? /\A\+[1-9][0-9]{7,14}\z/ : /\A[[:alnum:]][[:alnum:]_.:\/-]{0,119}\z/
        raise Invalid, "Enter a valid #{label.downcase}." unless format.match?(value)

        [key, value]
      end
    end

    def self.check_operator!(operator)
      raise Invalid, "Direct super administrator access is required." unless operator&.role == "super_admin" &&
        Current.session&.connect_delegation.blank?
    end

    private_class_method :validated_evidence
  end
end
