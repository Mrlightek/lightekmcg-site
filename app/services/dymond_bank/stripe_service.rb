module DymondBank
  class StripeService
    class ConfigurationError < StandardError; end
    class StripeError < StandardError; end

    class << self
      def create_connect_account!(user)
        configure!
        return retrieve_account(user.stripe_connect_account_id) if user.stripe_connect_account_id.present?

        account = Stripe::Account.create(
          {
            type: "express",
            country: "US",
            email: user.email_address,
            capabilities: { transfers: { requested: true } },
            metadata: { lightek_user_id: user.id.to_s, product: "susu" }
          },
          { idempotency_key: "lightek-connect-user-#{user.id}" }
        )

        user.update!(stripe_connect_account_id: account.id)
        sync_connect_status!(user, account: account)
        account
      rescue ::Stripe::StripeError => e
        raise StripeError, "The payout service could not complete this request. Refresh your payout connection or contact support."
      end

      def create_account_link!(user:, refresh_url:, return_url:)
        configure!
        account = create_connect_account!(user)
        Stripe::AccountLink.create(
          account: account.id,
          refresh_url: refresh_url,
          return_url: return_url,
          type: "account_onboarding"
        )
      rescue ::Stripe::StripeError => e
        raise StripeError, "The payout service could not complete this request. Refresh your payout connection or contact support."
      end

      def sync_connect_status!(user, account: nil)
        configure!
        account ||= retrieve_account(user.stripe_connect_account_id)
        LightekPayments::PayoutAccounts.persist_status!(user, account)
        account
      rescue ::Stripe::StripeError, StripeError, LightekPayments::PayoutAccounts::Unavailable => e
        LightekPayments::PayoutAccounts.invalidate!(user)
        raise StripeError, "The payout service could not complete this request. Refresh your payout connection or contact support."
      end

      def create_transfer(amount_cents:, currency:, destination_account:, description:, metadata: {}, idempotency_key: nil)
        configure!
        params = {
          amount: amount_cents.to_i,
          currency: currency.to_s.downcase,
          destination: destination_account,
          description: description,
          metadata: metadata
        }
        options = {}
        options[:idempotency_key] = idempotency_key if idempotency_key.present?
        Stripe::Transfer.create(params, options)
      rescue ::Stripe::StripeError => e
        raise StripeError, "The payout service could not complete this request. Refresh your payout connection or contact support."
      end

      def retrieve_account(account_id)
        configure!
        raise ConfigurationError, "Payout account setup is required" if account_id.blank?
        Stripe::Account.retrieve(account_id)
      rescue ::Stripe::StripeError => e
        raise StripeError, "The payout service could not complete this request. Refresh your payout connection or contact support."
      end

      private

      def configure!
        key = DymondBank::StripeCredentials.secret_key
        raise ConfigurationError, "Payouts are not configured yet" if key.blank?

        Stripe.api_key = key
      end
    end
  end
end
