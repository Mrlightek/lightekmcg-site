# frozen_string_literal: true
require "json"
require "digest"
require "pathname"
require "tmpdir"
module NevaehIntelligences
  # Read-only evidence audit. No user-provided Ruby evaluation, execution, or approval.
  module AcceptanceEvidenceV7a
    class Rejected < StandardError; end
    MAX_JSON_BYTES = 2_000_000
    ARTIFACTS = {
      "services/metadata_normalizer.rb" => "service_sha256",
      "jobs/metadata_normalization_job.rb" => "job_sha256"
    }.freeze
    module_function

    def inspect_bundle(destination:, root: Rails.root.to_s)
      raise Rejected, "local evidence access denied" unless TicketDraftAccessV7a.allowed?
      raise Rejected, "absolute directory required" unless destination.is_a?(String) && Pathname.new(destination).absolute?
      raise Rejected, "directory must exist" unless File.directory?(destination) && !File.symlink?(destination)
      base = File.realpath(destination)
      repo = File.realpath(root)
      raise Rejected, "repository output prohibited" if base == repo || base.start_with?(repo + File::SEPARATOR)
      # Browser and CLI reports are restricted to the platform temp area, not arbitrary machine paths.
      tmp = File.realpath(Dir.tmpdir)
      raise Rejected, "output must live under local temp" unless base.start_with?(tmp + File::SEPARATOR)
      raise Rejected, "not a reviewed candidate bundle" unless File.basename(base).start_with?("nevaeh-reviewed-") ||
        File.basename(File.dirname(base)).start_with?("nevaeh-reviewed-") || File.basename(base) == "candidate"
      trace = read_json(base, "ticket_traceability.json")
      manifest = read_json(base, "manifest.json")
      unit = read_json(base, "reviewed_candidate/verification.json")
      job = read_json(base, "reviewed_candidate/job_verification.json")
      raise Rejected, "invalid evidence types" unless [trace, manifest, unit, job].all? { |v| v.is_a?(Hash) }
      raise Rejected, "ticket mismatch" unless trace["ticket_id"] == job["ticket_id"]
      raise Rejected, "capability mismatch" unless trace["capability_key"] == job["capability"] && trace["capability_key"] == unit["capability"]
      raise Rejected, "unrecognized reviewed template" unless unit["template"] == "metadata.normalize.v1" && job["template"] == unit["template"]
      criteria = trace.fetch("acceptance_criteria")
      raise Rejected, "invalid acceptance criteria" unless criteria.is_a?(Array) && criteria.any? && criteria.all? { |c| c.is_a?(String) && !c.strip.empty? }
      digest_check = ->(file, expected) { expected.is_a?(String) && /\A[0-9a-f]{64}\z/.match?(expected) && Digest::SHA256.file(file).hexdigest == expected }
      manifest_path = safe_file(base, "manifest.json")
      integrity = { "generator_manifest" => digest_check.call(manifest_path, trace["generator_manifest_sha256"]) }
      ARTIFACTS.each do |relative, field|
        path = safe_file(base, "reviewed_candidate/#{relative}")
        integrity[relative] = digest_check.call(path, job[field]) && digest_check.call(path, unit.fetch("artifact_sha256", {})[relative])
      end
      # No generated or ticket-supplied assertion can certify coverage on its own.
      accepted = criteria.each_with_index.map do |criterion, index|
        { "criterion_index" => index + 1, "criterion" => criterion, "status" => "unverified",
          "linked_tests" => [], "reason" => "No independently reviewed test-to-criterion mapping" }
      end
      all_intact = integrity.values.all?
      service_pass = unit["service_unit_tests_passed"] == true && all_intact
      job_pass = job["job_integration_verified"] == true && all_intact
      {
        "schema_version" => 1, "type" => "acceptance_evidence_report", "status" => all_intact ? "awaiting_criterion_review" : "integrity_failure",
        "ticket_id" => trace["ticket_id"], "tracking_key" => trace["tracking_key"], "capability_key" => trace["capability_key"],
        "template" => unit["template"], "integrity" => integrity, "integrity_verified" => all_intact,
        "implementation_present" => all_intact, "service_tests_passed" => service_pass,
        "job_integration_tests_passed" => job_pass, "acceptance_criteria" => accepted,
        "acceptance_verified" => false, "gatekeeper_approved" => false, "production_allowed" => false,
        "source_promoted" => false, "report_only" => true
      }
    rescue JSON::ParserError, KeyError, TypeError, ArgumentError, Errno::ENOENT => e
      raise Rejected, "invalid or incomplete evidence: #{e.message}"
    end

    def safe_file(base, relative)
      path = File.join(base, relative)
      raise Rejected, "missing or symlinked artifact: #{relative}" unless File.file?(path) && !File.symlink?(path)
      resolved = File.realpath(path)
      raise Rejected, "artifact escapes bundle" unless resolved.start_with?(base + File::SEPARATOR)
      resolved
    end

    def read_json(base, relative)
      path = safe_file(base, relative)
      raise Rejected, "oversized JSON artifact" if File.size(path) > MAX_JSON_BYTES
      JSON.parse(File.read(path))
    end
  end
end
