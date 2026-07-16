#!/usr/bin/env bash
# Provisioning: one image, capabilities by manifest.
#
#   Marlon::Manifest      -> Purchase -> what their instance may run
#   Marlon::Capabilities  -> the gate INSIDE the image ("is billing on?")
#   Marlon::ProvisionHandler -> dispatch -> VPS (runner seam: local | remote)
#
# Run from the Rails app root.
#   cd ~/Desktop/Development/lightekmcg-site && bash build_provisioning.sh
set -uo pipefail
echo "==> Building provisioning ($(pwd))"
[ -f "config/application.rb" ] || { echo "  error: run from the Rails app root" >&2; exit 1; }
mkdir -p app/services/marlon

# ---------------- Manifest ----------------
cat > app/services/marlon/manifest.rb <<'RUBY'
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
RUBY
echo "  [1/4] Manifest"

# ---------------- Capabilities (the gate inside the image) ----------------
cat > app/services/marlon/capabilities.rb <<'RUBY'
# frozen_string_literal: true
module Marlon
  # THE GATE — this runs INSIDE a customer instance.
  #
  # The image ships all the code; this decides what's on. Reads the manifest from
  # MARLON_MANIFEST (raw JSON) or MARLON_MANIFEST_PATH (a file). With neither —
  # e.g. LightekMCG's own app — everything is enabled.
  #
  #   Marlon::Capabilities.enabled?(:billing)   # pack on?
  #   Marlon::Capabilities.feature?(:invoicing) # feature on?
  #   Marlon::Capabilities.mode                 # paid | trial | demo | free
  module Capabilities
    module_function

    def manifest
      return @manifest if defined?(@manifest) && @manifest

      @manifest = load_manifest || {}
    end

    def reload!
      @manifest = nil
      manifest
    end

    # No manifest => the mothership (or dev). Everything on.
    def unrestricted?
      manifest.empty?
    end

    def packs
      Array(manifest["packs"]).map(&:to_s)
    end

    def features
      Array(manifest["features"]).map(&:to_s)
    end

    def enabled?(pack)
      return true if unrestricted?
      packs.include?(pack.to_s)
    end

    def feature?(key)
      return true if unrestricted?
      features.include?(key.to_s)
    end

    def mode
      manifest["mode"] || "unrestricted"
    end

    def instance_id
      manifest["instance_id"]
    end

    def project_type
      manifest["project_type"]
    end

    def usage_billing?
      !!manifest.dig("billing", "usage_billing")
    end

    def load_manifest
      raw = ENV["MARLON_MANIFEST"].presence
      if raw.nil? && (path = ENV["MARLON_MANIFEST_PATH"].presence) && File.exist?(path)
        raw = File.read(path)
      end
      return nil if raw.nil?

      JSON.parse(raw)
    rescue StandardError => e
      Rails.logger.error "[capabilities] manifest unreadable: #{e.message}" if defined?(Rails)
      nil
    end
  end
end
RUBY
echo "  [2/4] Capabilities (the runtime gate)"

# ---------------- ProvisionHandler (dispatch contract) ----------------
cat > app/services/marlon/provision_handler.rb <<'RUBY'
# frozen_string_literal: true
module Marlon
  # dymond_dispatch handler: .perform(*args) -> Hash. Runs on the builds queue,
  # so a provision shows on the RTM wallboard next to transcodes.
  #
  # RUNNER SEAM (same shape as the transcode runner):
  #   :local  — dev. Logs the manifest, spins nothing.
  #   :remote — Dymond Server OS: Packer image + Ansible play -> VPS, manifest injected.
  #
  # MARLON_PROVISION_RUNNER=local|remote
  module ProvisionHandler
    module_function

    def perform(manifest = {})
      m = manifest.is_a?(Hash) ? manifest : JSON.parse(manifest.to_s)
      runner = (ENV["MARLON_PROVISION_RUNNER"].presence || "local").to_sym

      case runner
      when :remote then run_remote(m)
      else run_local(m)
      end
    end

    def run_local(m)
      Rails.logger.info(
        "[provision:local] instance=#{m['instance_id']} type=#{m['project_type']} " \
        "mode=#{m['mode']} packs=#{Array(m['packs']).size} features=#{Array(m['features']).size}"
      )
      {
        runner: "local",
        provisioned: false,
        reason: "local runner spins no VPS — set MARLON_PROVISION_RUNNER=remote",
        instance_id: m["instance_id"],
        project_type: m["project_type"],
        packs: m["packs"]
      }
    end

    # THE REAL ONE. Wire this to Dymond Server OS.
    #
    # Contract:
    #   1. Provision the VPS (OVH/Hetzner/Akamai) from the Packer image
    #   2. Ansible play: pull the app image, write the manifest, start
    #   3. Join the Nebula mesh (lightek-backbone); register with lightek-noc
    #   4. Return { host:, ip:, instance_id: } so the Purchase can record it
    #
    # The manifest goes to the instance as MARLON_MANIFEST (env) or a file at
    # MARLON_MANIFEST_PATH. Marlon::Capabilities reads it — that's the whole
    # activation mechanism.
    def run_remote(m)
      raise NotImplementedError,
            "Remote provisioning not wired. Connect Dymond Server OS (Packer/Ansible). " \
            "Manifest ready: instance=#{m['instance_id']} type=#{m['project_type']} " \
            "packs=#{Array(m['packs']).join(',')}"
    end
  end
end
RUBY
echo "  [3/4] ProvisionHandler (runner seam)"

# ---------------- Provisioning: fulfil -> dispatch ----------------
cat > app/services/marlon/provisioning.rb <<'RUBY'
# frozen_string_literal: true
module Marlon
  # What happens when a Purchase is paid: build the manifest, submit the
  # provision to dispatch (builds queue). One image, capabilities by manifest.
  module Provisioning
    module_function

    def fulfill(purchase)
      spec = purchase.provision_spec || {}

      if spec.blank? || spec["offerable_type"].blank?
        purchase.mark_provisioned!
        return { ok: true, provisioned: false, reason: "nothing to build" }
      end

      target = resolve(spec)
      unless target
        purchase.mark_failed!("provision target not found: #{spec['offerable_type']}##{spec['offerable_id']}")
        return { ok: false, error: "target not found" }
      end

      manifest = Marlon::Manifest.build(purchase)
      purchase.update!(instance_id: manifest["instance_id"]) if purchase.respond_to?(:instance_id)

      work = submit(manifest)
      purchase.mark_provisioning!(work_item_id: work.respond_to?(:id) ? work.id : nil)

      { ok: true, provisioned: true, instance_id: manifest["instance_id"],
        project_type: manifest["project_type"], packs: manifest["packs"], work_item: work }
    rescue StandardError => e
      purchase.mark_failed!(e.message)
      { ok: false, error: e.message }
    end

    def submit(manifest)
      if defined?(DymondDispatch::Dispatcher)
        DymondDispatch::Dispatcher.submit(
          "Marlon::ProvisionHandler",
          args: [manifest], queue: "builds", priority: 2,
          dispositions: [
            { "kind" => "broadcast", "stream" => "dymond_dispatch:rtm", "on" => "any" }
          ]
        )
      else
        Marlon::ProvisionHandler.perform(manifest)
      end
    end

    def resolve(spec)
      klass = spec["offerable_type"].to_s.safe_constantize
      return nil unless klass

      klass.find_by(id: spec["offerable_id"])
    rescue StandardError
      nil
    end

    def customer_for(spec)
      klass = spec["customer_type"].to_s.safe_constantize
      klass&.find_by(id: spec["customer_id"])
    rescue StandardError
      nil
    end
  end
end
RUBY
echo "  [4/4] Provisioning (fulfil -> manifest -> dispatch)"

echo ""
echo "==> Purchase needs instance_id + host columns — run this migration:"
cat <<'MIG'
    bin/rails g migration AddInstanceToDymondBankPurchases \
      instance_id:string:index instance_host:string
    bin/rails db:migrate
MIG
echo ""
echo "==> ruby -c app/services/marlon/*.rb"
