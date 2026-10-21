# frozen_string_literal: true
require "json"
require "digest"
module NevaehIntelligences
  # Read-only, untrusted evidence-link audit. Does not certify ticket acceptance.
  module AcceptanceCoverageV7a
    class Rejected < StandardError; end
    MAX_MAPPING_BYTES = 200_000
    ALLOWED_EVIDENCE = %w[service_unit_tests job_integration_tests].freeze
    module_function

    def inspect_bundle(destination:, root: Rails.root.to_s)
      base_report = AcceptanceEvidenceV7a.inspect_bundle(destination: destination, root: root)
      base = File.realpath(destination)
      criteria = base_report.fetch("acceptance_criteria")
      relative = "coverage_mapping.json"
      map_path = File.join(base, relative)
      mappings = []
      if File.exist?(map_path) || File.symlink?(map_path)
        file = AcceptanceEvidenceV7a.safe_file(base, relative)
        raise Rejected, "oversized coverage mapping" if File.size(file) > MAX_MAPPING_BYTES
        document = JSON.parse(File.read(file))
        raise Rejected, "wrong mapping schema" unless document.is_a?(Hash) && document.keys.sort == %w[mappings schema_version] && document["schema_version"] == 1 && document["mappings"].is_a?(Array)
        mappings = document.fetch("mappings")
        raise Rejected, "too many mappings" if mappings.size > criteria.size * 2
        seen = {}
        mappings.each do |item|
          raise Rejected, "invalid mapping shape" unless item.is_a?(Hash) && item.keys.sort == %w[criterion_index evidence_type]
          index = item["criterion_index"]
          kind = item["evidence_type"]
          raise Rejected, "invalid criterion reference" unless index.is_a?(Integer) && index.between?(1, criteria.size)
          raise Rejected, "unsupported evidence reference" unless ALLOWED_EVIDENCE.include?(kind)
          raise Rejected, "duplicate evidence reference" if seen[[index, kind]]
          seen[[index, kind]] = true
        end
      end
      intact = base_report.fetch("integrity_verified")
      report_criteria = criteria.map do |item|
        idx = item.fetch("criterion_index")
        links = mappings.select { |m| m.fetch("criterion_index") == idx }.map do |m|
          kind = m.fetch("evidence_type")
          passed = intact && (kind == "service_unit_tests" ? base_report.fetch("service_tests_passed") : base_report.fetch("job_integration_tests_passed"))
          { "evidence_type" => kind, "evidence_result" => passed ? "test_evidence_present" : "evidence_unverified" }
        end
        status = if !intact
          "integrity_failure"
        elsif links.empty?
          "unmapped"
        elsif links.all? { |l| l.fetch("evidence_result") == "test_evidence_present" }
          "mapped_pending_independent_review"
        else
          "evidence_unverified"
        end
        { "criterion_index" => idx, "criterion" => item.fetch("criterion"), "status" => status, "evidence_links" => links, "accepted" => false }
      end
      base_report.merge(
        "type" => "criterion_coverage_report", "coverage_schema_version" => 1,
        "mapping_present" => File.exist?(map_path),
        "mapping_sha256" => File.file?(map_path) && !File.symlink?(map_path) ? Digest::SHA256.file(map_path).hexdigest : nil,
        "acceptance_criteria" => report_criteria,
        "mapped_criteria_count" => report_criteria.count { |x| x.fetch("status") == "mapped_pending_independent_review" },
        "accepted_criteria_count" => 0,
        "acceptance_verified" => false, "gatekeeper_approved" => false,
        "source_promoted" => false, "production_allowed" => false, "report_only" => true
      )
    rescue JSON::ParserError, KeyError, TypeError, ArgumentError, AcceptanceEvidenceV7a::Rejected => e
      raise Rejected, "coverage audit refused: #{e.message}"
    end
  end
end
