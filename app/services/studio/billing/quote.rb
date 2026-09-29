# frozen_string_literal: true

module Studio
  module Billing
    class Quote
      DEFAULT_RAIL = :stripe_ach
      CONTEXTS = {
        "build_scene" => :studio_render
      }.freeze

      def self.call(operation:, rail: DEFAULT_RAIL)
        new(operation:, rail:).call
      end

      def initialize(operation:, rail:)
        @operation = operation
        @rail = rail.to_sym
      end

      def call
        principal_cents =
          Studio::Billing::Pricing.principal_cents_for(
            operation.operation_type
          )

        context = CONTEXTS.fetch(operation.operation_type) do
          raise ArgumentError,
                "No billing context configured for #{operation.operation_type.inspect}"
        end

        quote = DymondBank::PaymentQuote.call(
          principal_cents: principal_cents,
          rail: rail,
          context: context
        )

        payload = stringify_quote(quote).merge(
          "quoted_at" => Time.current.iso8601,
          "description" => description
        )

        operation.update!(
          cost_quote: payload,
          status: "awaiting_payment",
          error_message: nil
        )

        quote
      end

      private

      attr_reader :operation, :rail

      def stringify_quote(quote)
        quote.to_h.each_with_object({}) do |(key, value), result|
          result[key.to_s] =
            value.is_a?(Symbol) ? value.to_s : value
        end
      end

      def description
        case operation.operation_type
        when "build_scene"
          scene_name =
            operation.studio_scene&.name.presence ||
            "Studio Scene"

          "Studio render — #{scene_name}"
        else
          "Studio operation — #{operation.operation_type.humanize}"
        end
      end
    end
  end
end
