# frozen_string_literal: true

module DymondBank
  class StripeAccessCheck
    CHECKS = {
      'payments' => 'Payment Intents',
      'checkout' => 'Checkout Sessions',
      'subscriptions' => 'Subscriptions',
      'refunds' => 'Refunds',
      'connect' => 'Connected accounts',
      'transfers' => 'Connect transfers',
      'event_delivery' => 'Webhook endpoint configuration',
      'global_payouts' => 'Global Payouts financial account'
    }.freeze

    InvalidCheck = Class.new(ArgumentError)

    def self.call(actor:, check:)
      raise InvalidCheck, 'Choose an available Stripe access check.' unless CHECKS.key?(check)
      raise ActiveRecord::RecordNotFound unless actor&.role == 'super_admin'

      if check == 'global_payouts'
        adapter = WorkforcePayouts.new(employer: actor)
        mode = adapter.partner_sender.fetch(:live) ? 'live' : 'test'
        adapter.verify_sender!
      else
        key = StripeCredentials.secret_key.to_s
        return {state: 'unconfigured'} if key.blank?

        mode = key.match?(/\A(?:sk|rk)_live_/) ? 'live' : 'test'
        read_platform_resource(check, {api_key: key})
      end
      {state: 'read_access_verified', mode: mode}
    rescue ::Stripe::PermissionError
      {state: 'access_denied', mode: mode}
    rescue ::Stripe::StripeError, WorkforcePayouts::ProviderError, WorkforcePayouts::Unavailable
      {state: 'unverified', mode: mode}
    end

    def self.read_platform_resource(check, options)
      resource = case check
      when 'payments' then ::Stripe::PaymentIntent
      when 'checkout' then ::Stripe::Checkout::Session
      when 'subscriptions' then ::Stripe::Subscription
      when 'refunds' then ::Stripe::Refund
      when 'connect' then ::Stripe::Account
      when 'transfers' then ::Stripe::Transfer
      when 'event_delivery' then ::Stripe::WebhookEndpoint
      end
      resource.list({limit: 1}, options)
      nil
    end
    private_class_method :read_platform_resource
  end
end
