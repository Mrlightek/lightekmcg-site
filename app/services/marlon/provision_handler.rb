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
