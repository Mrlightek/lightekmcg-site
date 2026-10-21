# frozen_string_literal: true
require "json"
require "digest"
module NevaehIntelligences
  # Produces an immutable-in-memory, read-only review proposal from audited evidence.
  # Does not record decisions, authorize Gatekeeper, or alter ticket state.
  module AcceptanceReviewPacketV7a
    class Rejected < StandardError; end
    module_function
    def build(destination:, root: Rails.root.to_s)
      report = AcceptanceCoverageV7a.inspect_bundle(destination: destination, root: root)
      criteria = report.fetch("acceptance_criteria")
      raise Rejected, "invalid criteria" unless criteria.is_a?(Array) && criteria.any?
      evidence_ok = report.fetch("integrity_verified") == true
      # No self-attested test result constitutes independent ticket acceptance.
      gaps = criteria.select { |row| row.fetch("status") != "mapped_pending_independent_review" }
      packet = {
        "schema_version" => 1,
        "type" => "acceptance_review_packet",
        "status" => "review_requested",
        "ticket_id" => report.fetch("ticket_id"),
        "tracking_key" => report.fetch("tracking_key"),
        "capability_key" => report.fetch("capability_key"),
        "template" => report.fetch("template"),
        "artifact_integrity_verified" => evidence_ok,
        "integrity" => report.fetch("integrity"),
        "service_tests_passed" => report.fetch("service_tests_passed"),
        "job_integration_tests_passed" => report.fetch("job_integration_tests_passed"),
        "criteria" => criteria,
        "criteria_count" => criteria.size,
        "mapped_pending_review_count" => report.fetch("mapped_criteria_count"),
        "unverified_criteria_count" => gaps.size,
        "review_gaps" => gaps.map { |row| { "criterion_index" => row.fetch("criterion_index"), "status" => row.fetch("status") } },
        "allowed_proposed_decisions" => %w[request_changes reject recommend_further_review],
        "decision_recorded" => false,
        "independently_accepted" => false,
        "gatekeeper_approved" => false,
        "ticket_completed" => false,
        "source_promoted" => false,
        "production_allowed" => false,
        "read_only" => true
      }
      packet["fingerprint"] = Digest::SHA256.hexdigest(JSON.generate(packet))
      packet
    rescue AcceptanceCoverageV7a::Rejected, KeyError, TypeError, ArgumentError => e
      raise Rejected, "review packet refused: #{e.message}"
    end
  end
end
