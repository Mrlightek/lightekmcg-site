# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"

module NevaehIntelligences
  # Bridges a validated, persisted GitHub-derived ticket to an explicitly selected
  # existing YAML capability. Produces review-only evidence and inert Rails drafts.
  # No ticket mutations, code promotion, dispatch, shell execution, or approvals.
  module TicketCapabilityDraftBridgeV7a
    class Rejected < StandardError; end
    module_function

    def preview(ticket:, capability_key:, root: Rails.root.to_s, capability_snapshot: nil)
      raise Rejected, "test or explicitly opted-in local development required" unless TicketDraftAccessV7a.allowed?
      plan = GithubDevelopmentPlanV7a.from_ticket(ticket: ticket)
      draft = CapabilityCodeGeneratorV7a.plan(root: root, key: capability_key)
      raise Rejected, "capability must be disabled" unless draft.fetch("enabled") == false
      raise Rejected, "capability cannot authorize production" unless draft.fetch("production_execution") == false
      record = {
        "schema_version" => 1,
        "status" => "review_only",
        "ticket_id" => plan.fetch("ticket_id"),
        "tracking_key" => plan.fetch("tracking_key"),
        "source_url" => plan.fetch("source_url"),
        "development_plan_fingerprint" => plan.fetch("fingerprint"),
        "objective" => plan.fetch("objective"),
        "acceptance_criteria" => plan.fetch("acceptance_criteria"),
        "capability_key" => capability_key,
        "capability_plan" => draft,
        "association" => "explicit_manual_selection_not_automatically_inferred",
        "acceptance_verified" => false,
        "implementation_verified" => false,
        "gatekeeper_approved" => false,
        "executable" => false,
        "production_allowed" => false
      }
      unless capability_snapshot.nil?
        enriched_plan = StudioCapabilityEngineeringPlanV7a.from_ticket(ticket: ticket, capability_snapshot: capability_snapshot)
        record = StudioCapabilityDraftEvidenceV7a.attach(draft: record, original_plan: plan, enriched_plan: enriched_plan)
        match = StudioCapabilityAutoMatchV7a.resolve(plan: plan, capability_snapshot: capability_snapshot)
        record = StudioCapabilityDraftMatchV7a.attach(draft: record, plan: plan, match: match)
      end
      record["fingerprint"] = Digest::SHA256.hexdigest(JSON.generate(record))
      record
    rescue GithubDevelopmentPlanV7a::Rejected, CapabilityCodeGeneratorV7a::Invalid,
           YamlCapabilityRegistryV7a::Invalid, KeyError, TypeError, ArgumentError => e
      raise Rejected, "invalid ticket/capability pairing: #{e.message}"
    end

    def generate(ticket:, capability_key:, destination:, root: Rails.root.to_s, capability_snapshot: nil)
      record = preview(ticket: ticket, capability_key: capability_key, root: root, capability_snapshot: capability_snapshot)
      # Reuse the generator's directory isolation and no-overwrite protections.
      result = CapabilityCodeGeneratorV7a.generate(root: root, key: capability_key, destination: destination)
      begin
        base = File.realpath(destination)
        raise Rejected, "output missing manifest" unless File.file?(File.join(base, "manifest.json"))
        info = record.merge("generator_manifest_sha256" => Digest::SHA256.file(File.join(base, "manifest.json")).hexdigest)
        File.open(File.join(base, "ticket_traceability.json"), File::WRONLY | File::CREAT | File::EXCL, 0o600) do |f|
          f.write(JSON.pretty_generate(info) + "\n")
        end
        note = "# Ticket-linked inert draft\n\nTicket: #{record.fetch('tracking_key')}\n\n" \
          "Capability: #{capability_key}\n\nThis association was explicitly selected, not inferred. " \
          "Acceptance criteria are NOT verified. Gatekeeper approval and human release review remain required.\n"
        File.open(File.join(base, "TICKET_README.md"), File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(note) }
        info.merge("artifact_manifest" => result, "destination" => base)
      rescue StandardError
        # Newly generated directory is owned entirely by this operation.
        FileUtils.remove_entry_secure(destination) if File.directory?(destination) && !File.symlink?(destination)
        raise
      end
    end
  end
end
