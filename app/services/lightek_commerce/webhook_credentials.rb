module LightekCommerce
  class WebhookCredentials
    SLUG = 'lightek-commerce-webhook'.freeze
    CONSUMER = name.freeze
    PURPOSE = 'commerce_webhook'.freeze
    class Unavailable < StandardError; end
    def self.configured?
      return ENV['LIGHTEK_COMMERCE_STRIPE_WEBHOOK_SECRET'].present? unless defined?(LightekVault::Secret)
      record = LightekVault::Secret.table_exists? && LightekVault::Secret.find_by(slug: SLUG)
      return ENV['LIGHTEK_COMMERCE_STRIPE_WEBHOOK_SECRET'].present? unless record
      record.usable? && LightekVault::Policy.authorize(secret: record, consumer: CONSUMER, purpose: PURPOSE).allowed
    end
    def self.secret
      return ENV['LIGHTEK_COMMERCE_STRIPE_WEBHOOK_SECRET'].to_s.dup unless defined?(LightekVault::Secret)
      record = LightekVault::Secret.table_exists? && LightekVault::Secret.find_by(slug: SLUG)
      return ENV['LIGHTEK_COMMERCE_STRIPE_WEBHOOK_SECRET'].to_s.dup unless record
      payload = LightekVault::Service.checkout!(slug: SLUG, consumer: CONSUMER, purpose: PURPOSE, requested_by: 'commerce-webhook')
      value = payload.fetch('signing_secret').dup
      raise Unavailable, 'Payment callback signing key is unavailable' if value.blank?
      value
    rescue LightekVault::Service::AccessDenied, KeyError
      raise Unavailable, 'Payment callback signing key is unavailable'
    ensure
      payload&.each_value { |v| v.clear if v.is_a?(String) && !v.frozen? }
    end
    def self.store!(actor:, value:)
      raise LightekPwa::Policy::Denied, 'Platform super administrator access required' unless actor&.role == 'super_admin'
      raise ArgumentError, 'Enter the payment endpoint signing secret' unless value.to_s.match?(/\Awhsec_[A-Za-z0-9]{12,500}\z/)
      LightekVault::Service.store!(name: 'Commerce payment callbacks', slug: SLUG,
        payload: {'signing_secret'=>value}, secret_type: 'webhook_secret', purpose: PURPOSE,
        access_policy: {'consumers'=>[CONSUMER], 'purposes'=>[PURPOSE]}, requested_by: actor.email_address)
    end
  end
end
