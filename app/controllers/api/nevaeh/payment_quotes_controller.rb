module Api
  module Nevaeh
    class PaymentQuotesController < ApplicationController
      protect_from_forgery with: :exception

      def create
        principal_cents =
          Integer(
            params.require(:principal_cents)
          )

        rail =
          params
            .fetch(:rail, "stripe_ach")
            .to_sym

        context =
          params
            .fetch(:context, "payment")
            .to_sym

        raise ArgumentError,
              "principal_cents must be positive" \
          unless principal_cents.positive?

        quote =
          DymondBank::PaymentQuote.call(
            principal_cents: principal_cents,
            rail: rail,
            context: context
          )

        payload =
          if quote.respond_to?(:to_h)
            quote.to_h
          else
            {
              principal_cents:
                quote.principal_cents,

              processor_recovery_cents:
                quote.processor_recovery_cents,

              network_fee_cents:
                quote.network_fee_cents,

              display_network_fee_cents:
                quote.display_network_fee_cents,

              total_cents:
                quote.total_cents
            }
          end

        render json: {
          capability: "payments.quote",
          status: "completed",
          result: payload
        }
      rescue ActionController::ParameterMissing,
             ArgumentError => error

        render json: {
          capability: "payments.quote",
          status: "failed",
          error: error.message
        }, status: :unprocessable_entity
      end
    end
  end
end
