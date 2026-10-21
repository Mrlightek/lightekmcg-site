# frozen_string_literal: true
require "digest"
require "json"
require "pathname"
require_relative "yaml_capability_registry_v7a"

module NevaehIntelligences
  # Safe read-only desired-vs-observed file inventory. Never executes a service.
  module CapabilityReconcilerV7a
    class Invalid < StandardError; end
    # Service mappings must come from a reviewed, trusted registry, not the YAML itself.
    # A mapping is a repository-relative implementation path, not a Ruby constant.
    module_function

    def plan(root:, key:, service_paths: {})
      root_real = File.realpath(root)
      raise Invalid, "invalid service map" unless service_paths.is_a?(Hash)
      cap = YamlCapabilityRegistryV7a.read(root: root_real, key: key).fetch("capability")
      raise Invalid, "execution-enabled capability forbidden" unless cap.fetch("enabled") == false
      jobs = cap.fetch("jobs").map do |job|
        sid = job.fetch("service")
        rel = service_paths[sid]
        state, digest = inspect_file(root_real, rel)
        { "id" => job.fetch("id"), "service" => sid,
          "depends_on" => job.fetch("depends_on"),
          "state" => state, "implementation_path" => rel,
          "sha256" => digest, "action" => state == "present" ? "review_existing" : (state == "missing" ? "propose_generation" : "register_service_mapping") }
      end
      { "schema_version" => 1, "capability" => key, "mode" => "read_only",
        "execution_allowed" => false, "gatekeeper_required" => true,
        "jobs" => jobs, "ready_for_execution" => false,
        "next_steps" => ["review service mappings", "generate missing services in isolation", "test and document", "obtain Gatekeeper authorization"] }
    end

    def inspect_file(root, relative)
      return ["unmapped", nil] if relative.nil?
      unless relative.is_a?(String) && relative.match?(%r{\Aapp/services/[a-z0-9_]+(?:/[a-z0-9_]+)*\.rb\z})
        raise Invalid, "unsafe service mapping"
      end
      base = File.realpath(root)
      cursor = base
      relative.split("/").each do |part|
        cursor = File.join(cursor, part)
        raise Invalid, "symlink in service path" if File.symlink?(cursor)
      end
      path = File.join(base, relative)
      return ["missing", nil] unless File.file?(path)
      raise Invalid, "service path escapes repository" unless File.realpath(path).start_with?(base + File::SEPARATOR)
      ["present", Digest::SHA256.file(path).hexdigest]
    end
  end
end
