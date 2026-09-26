# frozen_string_literal: true

class SusuPublicController < ApplicationController
  allow_unauthenticated_access only: %i[home pricing onboarding]
  layout "susu_public"

  def home; end

  def pricing
    return unless defined?(DymondBank) && DymondBank.respond_to?(:configuration)

    config = DymondBank.configuration
    context_fees = config.respond_to?(:network_fee_cents_by_context) ? config.network_fee_cents_by_context.to_h : {}

    @network_fee_cents =
      context_fees[:susu] ||
      context_fees["susu"] ||
      (config.respond_to?(:network_fee_cents_flat) ? config.network_fee_cents_flat : nil)

    @ach_fee_rate = config.stripe_ach_fee_rate if config.respond_to?(:stripe_ach_fee_rate)
    @ach_fee_cap_cents = config.stripe_ach_fee_cap_cents if config.respond_to?(:stripe_ach_fee_cap_cents)
  end

  def onboarding; end
end
