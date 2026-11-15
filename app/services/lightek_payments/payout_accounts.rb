require 'digest'
require 'uri'
module LightekPayments
  class PayoutAccounts
    class Unavailable < StandardError
      attr_reader :replaceable, :code
      def initialize(message = 'Payout verification is temporarily unavailable. Please try again or contact support.', replaceable: false, code: 'verification_unavailable')
        @code = code
        @replaceable = replaceable
        super(message)
      end
    end
    COMPONENTS = %w[account-onboarding account-management].freeze

    def self.options
      key = DymondBank::StripeCredentials.secret_key.to_s
      raise Unavailable.new('Payouts are not configured yet. Contact your account administrator.', code: 'configuration_missing') if key.blank?
      {api_key: key}
    end

    def self.publishable_key(opts)
      provider = DymondBank::StripeCredentials
      value = provider.publishable_key if provider.respond_to?(:publishable_key)
      value = value.presence || ENV['LIGHTEK_PAYOUT_PUBLISHABLE_KEY'].presence || ENV['STRIPE_PUBLISHABLE_KEY'].presence
      mode = opts.fetch(:api_key).match?(/\A(?:sk|rk)_live_/) ? 'live' : 'test'
      raise Unavailable.new('Embedded payout fields are not configured. Use Open secure verification to continue.', code: 'embedded_configuration') unless value.to_s.start_with?("pk_#{mode}_")
      value
    end

    # Hosted verification needs only backend credentials. Missing browser
    # configuration must not block people from submitting payout information.
    def self.configuration_status
      opts = options
      publishable_key(opts)
      {hosted_ready: true, embedded_ready: true}
    rescue Unavailable => error
      {hosted_ready: error.code == 'embedded_configuration', embedded_ready: false, code: error.code}
    end

    def self.persist_status!(user, account)
      raise Unavailable unless account.id == user.stripe_connect_account_id
      owner = account.metadata.to_h.stringify_keys['lightek_user_id']
      raise Unavailable if owner.present? && owner != user.id.to_s
      transfers = account.capabilities.to_h.stringify_keys['transfers']
      user.update!(stripe_connect_details_submitted: !!account.details_submitted,
        stripe_connect_payouts_enabled: !!account.payouts_enabled && transfers == 'active',
        stripe_connect_onboarded_at: account.details_submitted ? (user.stripe_connect_onboarded_at || Time.current) : nil)
      account
    end

    def self.status(user)
      user.with_lock do
        return {state: 'not_started', replaceable: false} if user.stripe_connect_account_id.blank?
        account = Stripe::Account.retrieve(user.stripe_connect_account_id, options)
        persist_status!(user, account)
        state = if user.stripe_connect_ready?
          'ready'
        elsif account.requirements.to_h.stringify_keys['pending_verification'].present?
          'pending_verification'
        else
          'needs_information'
        end
        {state: state, replaceable: false}
      end
    rescue ::Stripe::StripeError => error
      invalidate!(user)
      report(user, error)
      {state: 'unavailable', replaceable: stale_reference?(error), code: stale_reference?(error) ? 'connection_unavailable' : 'verification_unavailable'}
    rescue Unavailable => error
      invalidate!(user)
      {state: 'unavailable', replaceable: false, code: error.code}
    end

    def self.session!(user, component: 'account-onboarding')
      raise Unavailable, 'Choose a valid payout setup step.' unless COMPONENTS.include?(component)
      opts = options
      public_key = publishable_key(opts)
      user.with_lock do
        account = ensure_account!(user, opts)
        persist_status!(user, account)
        session = Stripe::AccountSession.create({account: account.id, components: {
          account_onboarding: {enabled: true, features: {external_account_collection: true}},
          account_management: {enabled: true, features: {external_account_collection: true}}
        }}, opts)
        {client_secret: session.client_secret, publishable_key: public_key, component: component}
      end
    rescue ::Stripe::StripeError => error
      invalidate!(user)
      report(user, error)
      raise Unavailable.new(replaceable: stale_reference?(error), code: stale_reference?(error) ? 'connection_unavailable' : 'verification_unavailable')
    rescue Unavailable
      invalidate!(user)
      raise
    end

    def self.ensure_account!(user, opts)
      return Stripe::Account.retrieve(user.stripe_connect_account_id, opts) if user.stripe_connect_account_id.present?
      account = create_account!(user, opts, suffix: 'initial')
      user.update!(stripe_connect_account_id: account.id)
      account
    end

    def self.create_account!(user, opts, suffix:)
      host = ENV['LIGHTEK_DEPLOYED_SITE_HOST'].presence || 'lightekmcg.com'
      namespace = Digest::SHA256.hexdigest(host.downcase).first(20)
      Stripe::Account.create({type: 'express', country: 'US', email: user.email_address,
        capabilities: {transfers: {requested: true}},
        metadata: {lightek_user_id: user.id.to_s, lightek_host_key: namespace, product: 'lightek_payouts'}},
        opts.merge(idempotency_key: "lightek-payout-#{namespace}-#{user.id}-#{suffix}"))
    end

    # Provider-hosted fallback for browsers that cannot run embedded fields.
    def self.hosted_link!(user, refresh_url:, return_url:)
      opts = options
      user.with_lock do
        account = ensure_account!(user, opts)
        persist_status!(user, account)
        link = Stripe::AccountLink.create({account: account.id, type: 'account_onboarding',
          refresh_url: refresh_url, return_url: return_url}, opts)
        uri = URI.parse(link.url)
        raise Unavailable unless uri.is_a?(URI::HTTPS) && %w[connect.stripe.com accounts.stripe.com].include?(uri.host) && !uri.userinfo && uri.port == 443
        uri.to_s
      end
    rescue ::Stripe::StripeError => error
      invalidate!(user)
      report(user, error)
      raise Unavailable
    rescue URI::InvalidURIError
      raise Unavailable
    end

    # An inaccessible legacy reference is retained in an audit row. This never
    # migrates an old balance or treats a replacement as verified/ready.
    def self.replace_unavailable!(user)
      opts = options
      user.with_lock do
        old = user.stripe_connect_account_id
        raise Unavailable, 'No existing payout connection needs replacement.' if old.blank?
        begin
          Stripe::Account.retrieve(old, opts)
          raise Unavailable, 'This payout account is accessible. Use account management instead.'
        rescue ::Stripe::StripeError => error
          raise Unavailable unless stale_reference?(error)
        end
        platform = Stripe::Account.retrieve(nil, opts)
        generation = ConnectionChange.where(user: user).count + 1
        replacement = create_account!(user, opts, suffix: "replacement-#{generation}")
        ConnectionChange.create!(user: user, previous_account_id: old, replacement_account_id: replacement.id,
          platform_account_id: platform.id, livemode: opts[:api_key].match?(/\A(?:sk|rk)_live_/))
        user.update!(stripe_connect_account_id: replacement.id, stripe_connect_details_submitted: false,
          stripe_connect_payouts_enabled: false, stripe_connect_onboarded_at: nil)
      end
    rescue ::Stripe::StripeError => error
      report(user, error)
      raise Unavailable
    end

    def self.invalidate!(user)
      user.update_columns(stripe_connect_payouts_enabled: false) if user.persisted?
    end
    def self.stale_reference?(error)
      %w[account_invalid resource_missing].include?(error.respond_to?(:code) ? error.code : nil)
    end
    def self.report(user, error)
      Rails.logger.warn({event: 'payout_connection_failed', user_id: user.id, error_class: error.class.name,
        error_code: error.respond_to?(:code) ? error.code : nil}.to_json)
    end
    private_class_method :create_account!, :ensure_account!, :stale_reference?, :report
  end
end
