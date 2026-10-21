# frozen_string_literal: true
require "yaml"
require "json"
require "pathname"
require "fileutils"

module NevaehIntelligences
  # Declarative desired state only. No Rails boot, constantize, job execution or service invocation.
  module YamlCapabilityRegistryV7a
    class Invalid < StandardError; end
    KEY = /\A[a-z][a-z0-9]*(?:[._][a-z0-9]+)*\z/
    STEP = /\A[a-z][a-z0-9_]*\z/
    # This is a set of *registration identifiers*, not a service executor allowlist.
    # New services need separate code review and Gatekeeper wiring before execution.
    SERVICE_ID = /\A[a-z][a-z0-9]*(?:[._][a-z0-9]+)*\z/
    module_function

    def directory(root)
      base = File.realpath(root)
      path = File.join(base, "config", "nevaeh", "capabilities")
      raise Invalid, "capability directory missing" unless File.directory?(path)
      raise Invalid, "capability directory symlink forbidden" if File.symlink?(path)
      real = File.realpath(path)
      raise Invalid, "capability directory escapes repository" unless real.start_with?(base + File::SEPARATOR)
      real
    end

    def assert_key!(value)
      raise Invalid, "invalid capability key" unless value.is_a?(String) && value.length <= 100 && KEY.match?(value)
      value
    end

    def path(root, key)
      File.join(directory(root), "#{assert_key!(key)}.yml")
    end

    def draft(key)
      assert_key!(key)
      { "schema_version" => 1,
        "capability" => { "key" => key, "version" => 1, "enabled" => false,
          "description" => "Draft capability; implementation not yet verified",
          "authorization" => { "gatekeeper_required" => true, "production_execution" => false },
          "jobs" => [], "cli" => { "command" => "capabilities show #{key}" },
          "documentation" => { "status" => "draft" } } }
    end

    def validate!(data, expected_key: nil)
      raise Invalid, "YAML root must be a mapping" unless data.is_a?(Hash)
      raise Invalid, "unsupported schema version" unless data["schema_version"] == 1
      cap = data["capability"]
      raise Invalid, "missing capability mapping" unless cap.is_a?(Hash)
      key = assert_key!(cap["key"])
      raise Invalid, "capability key mismatch" if expected_key && key != expected_key
      raise Invalid, "unsupported capability version" unless cap["version"].is_a?(Integer) && cap["version"] > 0
      raise Invalid, "capabilities must begin disabled" unless cap["enabled"] == false
      auth = cap["authorization"]
      raise Invalid, "Gatekeeper and production guard required" unless auth.is_a?(Hash) && auth["gatekeeper_required"] == true && auth["production_execution"] == false
      jobs = cap["jobs"]
      raise Invalid, "jobs must be an array" unless jobs.is_a?(Array) && jobs.length <= 50
      names = []
      jobs.each do |job|
        raise Invalid, "job must be a mapping" unless job.is_a?(Hash)
        id = job["id"]
        raise Invalid, "invalid job ID" unless id.is_a?(String) && STEP.match?(id)
        raise Invalid, "duplicate job ID" if names.include?(id)
        service = job["service"]
        raise Invalid, "invalid service identifier" unless service.is_a?(String) && SERVICE_ID.match?(service)
        depends = job["depends_on"]
        raise Invalid, "dependencies must be an array" unless depends.is_a?(Array) && depends.all? { |d| d.is_a?(String) && STEP.match?(d) } && depends.uniq == depends
        names << id
      end
      jobs.each do |job|
        job.fetch("depends_on").each do |dep|
          raise Invalid, "unknown or forward job dependency" unless names.index(dep) < names.index(job.fetch("id")) if names.include?(dep)
          raise Invalid, "unknown job dependency" unless names.include?(dep)
        end
      end
      # Order-constrained graph forbids cycles. No arbitrary classes, script paths or executable handlers.
      raise Invalid, "CLI metadata missing" unless cap["cli"].is_a?(Hash) && cap["cli"]["command"].is_a?(String)
      raise Invalid, "documentation metadata missing" unless cap["documentation"].is_a?(Hash)
      data
    end

    def read(root:, key:)
      location = path(root, key)
      raise Invalid, "capability file not found" unless File.file?(location) && !File.symlink?(location)
      data = YAML.safe_load(File.read(location), permitted_classes: [], permitted_symbols: [], aliases: false)
      validate!(data, expected_key: key)
    rescue Psych::Exception => e
      raise Invalid, "invalid YAML: #{e.class}"
    end

    def list(root:)
      Dir.glob(File.join(directory(root), "*.yml")).sort.map do |location|
        key = File.basename(location, ".yml")
        assert_key!(key)
        { "key" => key, "valid" => true, "jobs" => read(root: root, key: key).dig("capability", "jobs").length }
      end
    end

    def create(root:, key:, write: false)
      data = draft(key)
      validate!(data, expected_key: key)
      if write
        location = path(root, key)
        raise Invalid, "capability already exists" if File.exist?(location) || File.symlink?(location)
        File.open(location, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(YAML.dump(data)) }
      end
      data
    end

    def add_job(root:, key:, id:, service:, after: [], write: false)
      data = read(root: root, key: key)
      raise Invalid, "invalid job identifier" unless id.is_a?(String) && STEP.match?(id)
      raise Invalid, "invalid service identifier" unless service.is_a?(String) && SERVICE_ID.match?(service)
      raise Invalid, "duplicate job ID" if data.dig("capability", "jobs").any? { |j| j["id"] == id }
      data.dig("capability", "jobs") << { "id" => id, "service" => service, "depends_on" => after }
      validate!(data, expected_key: key)
      if write
        location = path(root, key)
        original = File.read(location)
        tmp = "#{location}.tmp.#{Process.pid}"
        begin
          File.open(tmp, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(YAML.dump(data)) }
          # Reject racing changes instead of clobbering unrelated edits.
          raise Invalid, "configuration changed during update" unless File.read(location) == original && !File.symlink?(location)
          File.rename(tmp, location)
        ensure
          File.delete(tmp) if File.exist?(tmp)
        end
      end
      data
    end
  end
end
