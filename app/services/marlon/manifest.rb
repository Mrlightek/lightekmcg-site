# frozen_string_literal: true
require "securerandom"

module Marlon
  # What a customer instance is ALLOWED to run.
  #
  # One Docker image ships every pack's code. The manifest decides what's active
  # on a given instance. N customers, one artifact: patch once, roll the fleet.
  # A customer buying another pack is a manifest change, not a redeploy.
  module Manifest
    module_function

    VERSION = 1

    def build(purchase)
      offer = purchase.offer
      spec  = purchase.provision_spec || {}
      type  = Marlon::Provisioning.resolve(spec)
      packs = resolved_packs(type)

      {
        "manifest_version" => VERSION,
        "instance_id"      => purchase.instance_id.presence || SecureRandom.uuid,
        "issued_at"        => Time.current.iso8601,
        "purchase_id"      => purchase.id,
        "offer_slug"       => offer&.slug,
        "mode"             => purchase.mode,
        "customer" => {
          "type" => spec["customer_type"],
          "id"   => spec["customer_id"]
        },
        "project_type" => type&.key,
        "packs"        => packs.map(&:key),
        "features"     => packs.flat_map { |p| p.features.map(&:key) }.uniq,
        "billing" => {
          "interval"      => purchase.billing_interval,
          "usage_billing" => !!offer&.usage_billing,
          "amount_cents"  => purchase.amount_cents
        }
      }
    end

    def resolved_packs(type)
      return [] unless type
      type.resolved_capability_packs
    rescue StandardError
      []
    end

    def to_json_string(purchase)
      JSON.generate(build(purchase))
    end
  end
end
