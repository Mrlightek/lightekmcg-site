# frozen_string_literal: true

module Studio
  module Billing
    class Checkout
      class QuoteMissing < StandardError; end
      class AlreadyPaid < StandardError; end

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

        unless rail == :stripe_ach
          raise ArgumentError,
                "Studio checkout currently supports stripe_ach only"
        end

        DymondBank::StripeCheckoutService.create_for_payable!(
          payable: operation,
          payer: payer,
          principal_cents: quote.fetch("principal_cents").to_i,
          context: context,
          description: quote.fetch(
            "description",
            "Studio #{operation.operation_type.humanize}"
          ),
          success_url: success_url,
          cancel_url: cancel_url
        )
      end

      private

      attr_reader :operation, :payer, :success_url, :cancel_url
    end
  end
end
