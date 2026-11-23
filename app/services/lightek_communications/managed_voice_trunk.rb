# frozen_string_literal: true

require "securerandom"

module LightekCommunications
  class ManagedVoiceTrunk
    PURPOSE = "managed_voice_trunk"

    def self.destination
      prefix = ENV["LIGHTEK_VOICE_CARRIER_ACCOUNT"].to_s
      pop, setup, monthly = %w[LIGHTEK_VOICE_CARRIER_POP LIGHTEK_VOICE_MAX_SETUP_CENTS LIGHTEK_VOICE_MAX_MONTHLY_CENTS].map do |key|
        Integer(ENV[key].to_s, 10, exception: false)
      end
      return unless AsteriskVoice.configured? && prefix.match?(/\A[0-9]{6}\z/) &&
        pop&.positive? && setup&.between?(0, 1_000_000) && monthly&.between?(1, 1_000_000)

      { "managed" => true, "prefix" => prefix, "pop" => pop, "max_setup_cents" => setup, "max_monthly_cents" => monthly }
    end

    def self.checkout!(add_on)
      LightekVault::Service.checkout!(slug: slug(add_on), consumer: name, purpose: PURPOSE,
        requested_by: "voice-order:#{add_on.order_id}")
    end

    def self.slug(add_on)
      "managed-voice-order-#{add_on.order_id}"
    end

    def initialize(add_on, carrier)
      @add_on = add_on
      @carrier = carrier
    end

    def register!(destination)
      details = credentials!(destination)
      @carrier.ensure_subaccount!(account: details.fetch("account"), password: details.fetch("trunk_password"),
        description: details.fetch("description"))
      AsteriskVoice.new(@add_on.order_id, details).register!
      @carrier.verify!(account: details.fetch("account"))
      details
    end

    private

    def credentials!(destination)
      self.class.checkout!(@add_on)
    rescue ActiveRecord::RecordNotFound
      suffix = "lt#{@add_on.order_id.to_s(36)}#{SecureRandom.hex(4)}"
      slug = self.class.slug(@add_on)
      details = {
        "account" => "#{destination.fetch('prefix')}_#{suffix}",
        "description" => "Lightek Voice #{suffix}",
        "host" => @carrier.server_for_pop!(destination.fetch("pop")),
        "trunk_password" => "Lt7#{SecureRandom.hex(12)}",
        "device_password" => "Lt7#{SecureRandom.hex(16)}"
      }
      LightekVault::Service.store!(name: "Voice credentials for order ##{@add_on.order_id}", slug: slug,
        payload: details, purpose: PURPOSE, access_policy: { "consumers" => [self.class.name], "purposes" => [PURPOSE] },
        requested_by: "voice-order:#{@add_on.order_id}")
      details
    end
  end
end
