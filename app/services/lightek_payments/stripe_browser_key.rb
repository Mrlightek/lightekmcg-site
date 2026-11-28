# frozen_string_literal: true

module LightekPayments
  class StripeBrowserKey
    class Invalid < StandardError; end

    SLUG = 'stripe-production'
    CONSUMER = 'DymondBank::StripeCredentials'
    PURPOSE = 'payment_processing'
    FIELD = 'publishable_key'

    def self.read
      return unless defined?(LightekVault::Service) && LightekVault::Secret.exists?(slug: SLUG)

      LightekVault::Service.checkout!(slug: SLUG, consumer: CONSUMER, purpose: PURPOSE,
        requested_by: CONSUMER)[FIELD].presence
    rescue LightekVault::Service::AccessDenied, LightekVault::Crypto::DecryptionError,
        LightekVault::MasterKey::ConfigurationError, ActiveRecord::RecordNotFound
      nil
    end

    def self.update!(actor:, key:)
      raise Invalid, 'Super administrator access is required.' unless actor&.role == 'super_admin'

      mode = key.to_s[/\Apk_(live|test)_[A-Za-z0-9]{8,}\z/, 1]
      processor_mode = DymondBank::StripeCredentials.secret_key.to_s[/\A(?:sk|rk)_(live|test)_/, 1]
      unless mode && mode == processor_mode
        raise Invalid, 'Enter the Stripe publishable key for the configured payment mode.'
      end

      secret = LightekVault::Secret.find_by!(slug: SLUG)
      secret.with_lock do
        decision = LightekVault::Policy.authorize(secret: secret, consumer: CONSUMER, purpose: PURPOSE)
        raise Invalid, 'The existing Stripe credential is unavailable.' unless decision.allowed

        crypto = LightekVault::Crypto.new
        payload = crypto.decrypt_hash(secret)
        secret.update!(**crypto.encrypt_hash(payload.merge(FIELD => key)), last_rotated_at: Time.current)
        LightekVault::Service.audit!(secret: secret, action: 'replaced', requested_by: actor.email_address,
          consumer: CONSUMER, purpose: PURPOSE, allowed: true, reason: 'Stripe publishable key updated')
      end
    rescue LightekVault::Crypto::DecryptionError, LightekVault::MasterKey::ConfigurationError, ActiveRecord::RecordNotFound
      raise Invalid, 'The existing Stripe credential is unavailable in Vault.'
    end
  end
end
