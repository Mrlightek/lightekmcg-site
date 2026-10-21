# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"
require "pathname"
require "tmpdir"

module NevaehIntelligences
  # Generates inert Rails-style files into a new isolated directory.
  # No application patching, constantize, execution, or authorization grants.
  module CapabilityCodeGeneratorV7a
    class Invalid < StandardError; end
    module_function

    def plan(root:, key:)
      registry = NevaehIntelligences::YamlCapabilityRegistryV7a
      data = registry.read(root: root, key: key)
      cap = data.fetch("capability")
      jobs = cap.fetch("jobs")
      raise Invalid, "capability must remain disabled" unless cap.fetch("enabled") == false
      raise Invalid, "production execution forbidden" unless cap.fetch("authorization").fetch("production_execution") == false
      raise Invalid, "too many jobs" if jobs.length > 20
      raise Invalid, "no configured jobs" if jobs.empty?
      jobs.each do |job|
        raise Invalid, "untrusted service naming" unless /\A[a-z][a-z0-9]*(?:\.[a-z][a-z0-9]*)+\z/.match?(job.fetch("service"))
      end
      known = NevaehIntelligences::TrustedServiceCatalogV7a.paths(root: root)
      items = jobs.map do |job|
        id = job.fetch("id")
        service = job.fetch("service")
        rel = known[service]
        { "job" => id, "service" => service, "dependencies" => job.fetch("depends_on"),
          "catalog_state" => rel ? "registered" : "unmapped",
          "path" => rel }
      end
      { "ticket_capability" => key, "enabled" => false, "production_execution" => false,
        "jobs" => items, "generator" => "nevaeh.capability_code_generator.v7a" }
    end

    def generate(root:, key:, destination:)
      proposal = plan(root: root, key: key)
      base = File.expand_path(destination)
      raise Invalid, "output must not be inside repository" if base == File.realpath(root) || base.start_with?(File.realpath(root) + File::SEPARATOR)
      raise Invalid, "output already exists" if File.exist?(base) || File.symlink?(base)
      raise Invalid, "output parent missing" unless File.directory?(File.dirname(base))
      parent = File.realpath(File.dirname(base))
      raise Invalid, "output parent inside repository" if parent == File.realpath(root) || parent.start_with?(File.realpath(root) + File::SEPARATOR)
      raise Invalid, "output parent symlink forbidden" if File.symlink?(File.dirname(base))
      created = false
      begin
        Dir.mkdir(base, 0o700)
        created = true
        files = {}
        proposal.fetch("jobs").each do |item|
          # Use job identifiers, not untrusted class or file names from YAML.
          id = item.fetch("job")
          klass = id.split("_").map(&:capitalize).join
          service_id = item.fetch("service")
          dirname = File.join(base, "jobs")
          FileUtils.mkdir_p(dirname)
          rel = "jobs/#{id}_job.rb"
          source = "# frozen_string_literal: true\n# Generated draft: #{key} / #{id}\n# Requested service: #{service_id}\nmodule NevaehGenerated\n  class #{klass}Job < ActiveJob::Base\n    queue_as :default\n    def perform(**_inputs)\n      raise NotImplementedError, \"Unimplemented generated job; requires Gatekeeper review\"\n    end\n  end\nend\n"
          File.write(File.join(base, rel), source)
          files[rel] = Digest::SHA256.hexdigest(source)
          testrel = "tests/#{id}_job_test.rb"
          FileUtils.mkdir_p(File.join(base, "tests"))
          test_source = "# frozen_string_literal: true\n# Pending contract test for #{key}:#{id}\n# Required dependency checks: #{item.fetch('dependencies').join(', ')}\n# NOTE: Feature tests must be authored before implementation approval.\n"
          File.write(File.join(base, testrel), test_source)
          files[testrel] = Digest::SHA256.hexdigest(test_source)
          service_rel = "services/#{id}_service.rb"
          FileUtils.mkdir_p(File.join(base, "services"))
          service_source = "# frozen_string_literal: true\n# Service draft for #{key}: #{service_id}\nmodule NevaehGenerated\n  class #{klass}Service\n    def self.call(**_inputs)\n      raise NotImplementedError, \"Service implementation and approval required\"\n    end\n  end\nend\n"
          File.write(File.join(base, service_rel), service_source)
          files[service_rel] = Digest::SHA256.hexdigest(service_source)
        end
        overview = "# Generated Nevaeh Capability Draft\n\nCapability: `#{key}`\n\n**Status: draft, disabled, not implemented, not executable.**\n\nJobs and dependencies:\n" + proposal.fetch("jobs").map { |i| "- `#{i.fetch('job')}` -> `#{i.fetch('service')}` (after: #{i.fetch('dependencies').join(', ')})" }.join("\n") + "\n\nNext: implement service behavior, author real tests, register approved mappings, Gatekeeper review.\n"
        File.write(File.join(base, "README.md"), overview)
        files["README.md"] = Digest::SHA256.hexdigest(overview)
        manifest = proposal.merge("artifact_sha256" => files, "verified_implementation" => false, "executable" => false)
        File.write(File.join(base, "manifest.json"), JSON.pretty_generate(manifest) + "\n")
        manifest
      rescue StandardError
        FileUtils.remove_entry_secure(base) if created && File.directory?(base)
        raise
      end
    end
  end
end
