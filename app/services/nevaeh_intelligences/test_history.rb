# frozen_string_literal: true
require "json"
require "digest"
require "pathname"
require "time"
module NevaehIntelligences
  # Import reports produced by bin/nevaeh-test. Reports are inert evidence, never instructions.
  class TestHistory
    class InvalidReport < StandardError; end
    def self.import_all!(root: Rails.root)
      base = Pathname(root).join("tmp/nevaeh/test_runs")
      return [] unless base.directory?
      base.glob("*.json").sort.map { |file| import!(file, root: root) }
    end

    def self.import!(file, root: Rails.root)
      root = Pathname(root).realpath
      directory = root.join("tmp/nevaeh/test_runs")
      path = Pathname(file)
      path = root.join(path) unless path.absolute?
      raise InvalidReport, "Report must be a regular file" unless path.file? && !path.symlink?
      path = path.realpath
      raise InvalidReport, "Report is outside test_runs" unless path.dirname == directory.realpath
      raw = JSON.parse(path.read)
      raise InvalidReport, "Unsupported report" unless raw.is_a?(Hash) && raw["schema_version"] == 1 && raw["source"] == "nevaeh-test"
      run_id = raw["run_id"].to_s
      raise InvalidReport, "Invalid run_id" unless /\A[0-9]{8}T[0-9]{6}-[0-9a-f]{12}\z/.match?(run_id) && path.basename.to_s == "#{run_id}.json"
      relative_log = "tmp/nevaeh/test_runs/#{run_id}.log"
      raise InvalidReport, "Unexpected output path" unless raw["output_path"] == relative_log
      output = root.join(relative_log)
      raise InvalidReport, "Output log missing or linked" unless output.file? && !output.symlink?
      digest = Digest::SHA256.file(output).hexdigest
      raise InvalidReport, "Output checksum mismatch" unless digest == raw["output_sha256"]
      status = raw["status"].to_s
      raise InvalidReport, "Invalid status" unless %w[passed failed].include?(status)
      exit_status = Integer(raw["exit_status"])
      raise InvalidReport, "Inconsistent status" unless (exit_status == 0) == (status == "passed")
      counts = raw["counts"].is_a?(Hash) ? raw["counts"] : {}
      count = ->(name) { counts[name].nil? ? nil : Integer(counts[name]) }
      ticket_id = Integer(raw["ticket_id"], exception: false)
      slug = raw["capability"].to_s.presence
      capability = slug && NevaehCapability.find_by(slug: slug)
      ticket = ticket_id && Marlon::Ticket.find_by(id: ticket_id)
      record = NevaehTestRun.find_or_initialize_by(run_id: run_id)
      # A run ID represents immutable evidence. Reject changed imports.
      if record.persisted? && (record.output_sha256 != digest || record.report != raw)
        raise InvalidReport, "Previously ingested run was modified"
      end
      record.assign_attributes(
        status: status, capability_slug: slug, nevaeh_capability: capability,
        marlon_ticket: ticket, correlation_id: raw["correlation_id"], git_sha: raw["git_sha"],
        environment: raw["environment"], exit_status: exit_status,
        tests_count: count.call("tests"), assertions_count: count.call("assertions"),
        failures_count: count.call("failures"), errors_count: count.call("errors"),
        skips_count: count.call("skips"), duration_seconds: raw["duration_seconds"],
        started_at: Time.iso8601(raw.fetch("started_at")), finished_at: Time.iso8601(raw.fetch("finished_at")),
        output_sha256: digest, report_path: path.relative_path_from(root).to_s,
        output_path: relative_log, report: raw
      )
      record.save!
      record
    rescue JSON::ParserError, ArgumentError, TypeError, KeyError => error
      raise InvalidReport, "Invalid test report: #{error.message}"
    end
  end
end
