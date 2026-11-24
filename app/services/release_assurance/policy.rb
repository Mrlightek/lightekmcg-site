# frozen_string_literal: true

module ReleaseAssurance
  module Policy
    class Denied < StandardError; end

    def self.authorize!(actor, candidate = nil)
      Gatekeeper::WebsiteDeployment.authorize!(actor)
      raise Denied, "Operator access is suspended" unless LightekPeople::LifecycleAccess.active?(actor)
      raise Denied, "Release belongs to another operator" if candidate && candidate.operator_id != actor.id
    rescue Gatekeeper::WebsiteDeployment::Invalid
      raise Denied, "A super administrator is required"
    end

    # Deployment and candidate publication use a dedicated worker with staging-only credentials.
    def self.runner!
      raise Denied, "A dedicated staging control plane is required" unless ENV["LIGHTEK_RELEASE_ASSURANCE_RUNNER"] == "1"
    end

    def self.hostname!(hostname)
      zone = ENV.fetch("LIGHTEK_RELEASE_ASSURANCE_ZONE", "")
      unless zone.match?(/\Astaging\.(?:[a-z0-9-]+\.)+[a-z]{2,}\z/) &&
          hostname.match?(/\Abatch-d-[a-z0-9]+(?:-[a-z0-9]+)*\.#{Regexp.escape(zone)}\z/)
        raise Denied, "Use a unique batch-d hostname in the configured staging zone"
      end
      hostname
    end
  end
end
