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
        raise StripeError, e.message
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
        raise StripeError, e.message
      end

      def sync_connect_status!(user, account: nil)
        configure!
        account ||= retrieve_account(user.stripe_connect_account_id)
        user.update!(
          stripe_connect_details_submitted: !!account.details_submitted,
          stripe_connect_payouts_enabled: !!account.payouts_enabled,
          stripe_connect_onboarded_at: (account.details_submitted ? (user.stripe_connect_onboarded_at || Time.current) : nil)
        )
        account
      rescue ::Stripe::StripeError => e
        raise StripeError, e.message
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
        raise StripeError, e.message
      end

      def retrieve_account(account_id)
        configure!
        raise ConfigurationError, "Stripe Connect account is missing" if account_id.blank?
        Stripe::Account.retrieve(account_id)
      rescue ::Stripe::StripeError => e
        raise StripeError, e.message
      end

      private

      def configure!
        key = DymondBank::StripeCredentials.secret_key
        raise ConfigurationError, "Stripe secret key is missing" if key.blank?

        Stripe.api_key = key
      end
    end
  end
end
