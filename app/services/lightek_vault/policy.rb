module LightekVault
  class Policy
    Decision = Data.define(:allowed, :reason)

    def self.authorize(secret:, consumer:, purpose:)
      new(secret:, consumer:, purpose:).authorize
    end

    def initialize(secret:, consumer:, purpose:)
      @secret = secret
      @consumer = consumer.to_s
      @purpose = purpose.to_s
    end

    def authorize
      return Decision.new(false, "secret is disabled") if secret.disabled?
      return Decision.new(false, "secret is expired") if secret.expired?

      policy = secret.access_policy.to_h
      consumers = Array(policy["consumers"]).map(&:to_s)
      purposes = Array(policy["purposes"]).map(&:to_s)

      return Decision.new(false, "consumer is not allowed") if consumers.any? && !consumers.include?(consumer)
      return Decision.new(false, "purpose is not allowed") if purposes.any? && !purposes.include?(purpose)

      Decision.new(true, "policy allows access")
    end

    private

    attr_reader :secret, :consumer, :purpose
  end
end
