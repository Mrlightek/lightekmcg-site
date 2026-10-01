# frozen_string_literal: true

module Studio
  module Billing
    class Checkout
      class QuoteMissing < StandardError; end
      class AlreadyPaid < StandardError; end

      SUPPORTED_RAILS = %i[
        stripe_ach
        stripe_card
      ].freeze

      def self.call(operation:, payer:, success_url:, cancel_url:)
        new(
          operation:,
          payer:,
          success_url:,
          cancel_url:
        ).call
      end

      def initialize(operation:, payer:, success_url:, cancel_url:)
        @operation = operation
        @payer = payer
        @success_url = success_url
        @cancel_url = cancel_url
      end

      def call
        raise AlreadyPaid, "Studio operation is already paid" if operation.paid?

        quote = operation.cost_quote.to_h

        if quote.blank? || quote["principal_cents"].to_i <= 0
          raise QuoteMissing,
                "Studio operation must have a valid quote before checkout"
        end

        rail = quote.fetch("rail", "stripe_ach").to_sym
        context = quote.fetch("context", "studio_render").to_sym

        unless SUPPORTED_RAILS.include?(rail)
          raise ArgumentError,
                "Unsupported Studio payment rail: #{rail.inspect}"
        end

        DymondBank::StripeCheckoutService.create_for_payable!(
          payable: operation,
          payer: payer,
          principal_cents: quote.fetch("principal_cents").to_i,
          context: context,
          description: quote.fetch(
            "description",
            "Studio Render"
          ),
          success_url: success_url,
          cancel_url: cancel_url,
          rail: rail
        )
      end

      private

      attr_reader :operation, :payer, :success_url, :cancel_url
    end
  end
end
