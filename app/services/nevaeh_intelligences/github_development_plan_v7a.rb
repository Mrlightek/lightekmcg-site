# frozen_string_literal: true
require "digest"
require "json"

module NevaehIntelligences
  # Produces a reviewable, non-executable planning envelope from an existing
  # GitHub-derived Work Order. Does not assert that code has been implemented.
  module GithubDevelopmentPlanV7a
    class Rejected < StandardError; end
    VERSION = 1
    module_function

    def from_ticket(ticket:)
      raise Rejected, "planning restricted to test or explicitly opted-in local development" unless TicketDraftAccessV7a.allowed?
      raise Rejected, "persisted Marlon ticket required" unless ticket.is_a?(Marlon::Ticket) && ticket.persisted?
      ticket.reload
      raise Rejected, "resolved ticket" if ticket.status == "resolved"
      data = ticket.extra_fields.to_h.deep_stringify_keys
      order = NevaehIntelligences::WorkOrder.read!(ticket: ticket)
      raise Rejected, "missing Work Order" unless order.is_a?(Hash)
      order = order.deep_stringify_keys
      input = order.fetch("inputs")
      key = input.fetch("tracking_key")
      raise Rejected, "identity mismatch" unless data.dig("project_tracking", "key") == key
      raise Rejected, "unsupported source" unless input["source"] == "github_issue" && input["source_repository"] == GithubIssueContractV7a::REPOSITORY
      raise Rejected, "unsupported order" unless order["work_type"] == "build" && order["intent_key"] == "github:#{GithubIssueContractV7a::REPOSITORY}:#{key}"
      raise Rejected, "missing import receipt" unless data.dig("nevaeh_github_import", "proposal_fingerprint") == input["proposal_fingerprint"]
      raise Rejected, "reserved ticket" if data.dig("nevaeh", "execution_status").present? || data.dig("nevaeh", "work_item_id").present?
      policy = order.fetch("execution_policy")
      raise Rejected, "unsafe policy" unless policy["environment"] == "test" && policy["approval"] == "gatekeeper" && policy["execution_enabled"] == false && policy["production_allowed"] == false && policy["requires_human_release_approval"] == true
      raise Rejected, "invalid objective" unless order["objective"].is_a?(String) && order["objective"].strip.length.between?(1, 20000)
      criteria = order.fetch("acceptance_criteria")
      raise Rejected, "invalid acceptance criteria" unless criteria.is_a?(Array) && criteria.any? && criteria.all? { |s| s.is_a?(String) && s.present? }
      plan = {
        "schema_version" => VERSION,
        "status" => "planning_only",
        "ticket_id" => ticket.id,
        "tracking_key" => key,
        "source_url" => input.fetch("source_url"),
        "work_order_intent_key" => order.fetch("intent_key"),
        "objective" => order.fetch("objective"),
        "requested_feature" => input.fetch("requested_feature"),
        "roadmap" => { "phase" => input.fetch("roadmap_phase"), "area" => input.fetch("roadmap_area"), "priority" => input.fetch("priority") },
        "required_capability" => "capability.build",
        "capability_resolution" => "unverified_requires_repository_and_registry_inspection",
        "steps" => [
          { "id" => "inspect", "kind" => "analysis", "task" => "Inspect current Rails code, capability registry, tests, and KB for existing implementations and dependencies" },
          { "id" => "design", "kind" => "analysis", "task" => "Derive file-level implementation and dependency plan from ticket objective, repository evidence, and applicable KB policy" },
          { "id" => "implement", "kind" => "controlled_development", "task" => "Implement scoped feature in an isolated non-production workspace; do not run generated instructions directly" },
          { "id" => "verify", "kind" => "verification", "task" => "Run scoped and regression tests; retain artifacts, diffs, and failure evidence" },
          { "id" => "register", "kind" => "review", "task" => "On verified result, propose capability registry and KB updates, linking source issue and tests" },
          { "id" => "release", "kind" => "approval", "task" => "Require human approval for any source promotion or production deployment" }
        ],
        "acceptance_criteria" => criteria,
        "dependencies" => ["repository_inspection", "capability_registry_lookup", "knowledge_base_policy_lookup", "isolated_development_executor"],
        "gatekeeper" => { "authorization_required" => true, "scoped_execution_only" => true, "production_execution_allowed" => false, "human_release_approval_required" => true },
        "execution_enabled" => false,
        "planning_limits" => "This is a deterministic work breakdown, not AI reasoning, code generation, capability discovery, or an executable authorization."
      }
      plan["fingerprint"] = Digest::SHA256.hexdigest(JSON.generate(plan))
      deep_freeze(plan)
    rescue KeyError, TypeError, ArgumentError
      raise Rejected, "invalid Work Order fields"
    end

    # Native historical tickets need an inspectable plan even when they did not
    # originate in GitHub. This is planning data, never an execution permission.
    def from_native_ticket(ticket:, knowledge_article_ids:, capability_snapshot:)
      raise Rejected, "persisted Marlon ticket required" unless ticket.is_a?(Marlon::Ticket) && ticket.persisted?
      fields = ticket.extra_fields.to_h.deep_stringify_keys
      order = fields["nevaeh_work_order"]
      order = WorkOrder.validate!(order) if order
      requirement = order&.fetch("intent_key") || fields["required_capability"]
      criteria = order&.fetch("acceptance_criteria") || fields["acceptance_criteria"] || []
      raise Rejected, "invalid acceptance criteria" unless criteria.is_a?(Array) && criteria.all? { |v| v.is_a?(String) && v.present? }
      steps = [
        {"id" => "inspect", "kind" => "analysis", "task" => "Inspect repository implementation and ticket dependencies"},
        {"id" => "knowledge", "kind" => "analysis", "task" => "Review linked KB procedures and capability contracts"},
        {"id" => "implement", "kind" => "controlled_development", "task" => "Execute the saved work order through Gatekeeper or escalate missing executor"},
        {"id" => "verify", "kind" => "verification", "task" => "Verify each acceptance criterion against persisted implementation evidence"},
        {"id" => "learn", "kind" => "review", "task" => "Record verified procedure in the existing Knowledge Base"},
        {"id" => "close", "kind" => "review", "task" => "Resolve only after acceptance and Knowledge Base persistence succeed"}
      ]
      plan = {
        "schema_version" => VERSION, "status" => "planning_only", "ticket_id" => ticket.id,
        "source" => "marlon_ticket", "objective" => order&.fetch("objective") || ticket.description.presence || ticket.title,
        "required_capability" => requirement, "acceptance_criteria" => criteria,
        "knowledge_article_ids" => knowledge_article_ids,
        "capability_resolution" => "unverified_requires_repository_and_registry_inspection",
        "dependencies" => fields.fetch("depends_on_ticket_ids", []), "steps" => steps,
        "gatekeeper" => {"authorization_required" => true, "production_execution_allowed" => false,
          "human_release_approval_required" => true}, "execution_enabled" => false
      }
      # Reuse STUDIO-203's exact-match bridge; registry presence is not proof.
      if requirement.to_s.match?(/\A[a-z][a-z0-9_.-]*\z/)
        plan = StudioCapabilityPlanResolutionV7a.attach(plan: plan, capability_snapshot: capability_snapshot).dup
      end
      plan["fingerprint"] = Digest::SHA256.hexdigest(JSON.generate(plan))
      deep_freeze(plan)
    end

    def deep_freeze(value)
      case value
      when Hash then value.each { |k, v| deep_freeze(k); deep_freeze(v) }
      when Array then value.each { |v| deep_freeze(v) }
      end
      value.freeze
    end
  end
end
