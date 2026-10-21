# frozen_string_literal: true
require "digest"
require "json"

module NevaehIntelligences
  # Existing Marlon::Ticket is canonical. This class does not create tickets,
  # grant authorizations, enqueue jobs, or execute generated code.
  module GithubTicketPersistenceV7a
    class Rejected < StandardError; end
    module_function

    def attach!(ticket:, proposal:)
      raise Rejected, "test environment only" unless Rails.env.test?
      raise Rejected, "persisted Marlon ticket required" unless ticket.is_a?(Marlon::Ticket) && ticket.persisted?
      raise Rejected, "ticket must be unresolved" if ticket.status == "resolved"
      p = normalize_proposal!(proposal)
      order = to_order(p)
      NevaehIntelligences::WorkOrder.validate!(order)
      key = p.fetch("inputs").fetch("tracking_key")
      # PostgreSQL advisory transaction lock protects tracking-key lookup across
      # distinct ticket rows, not just concurrent updates of one row.
      result = nil
      Marlon::Ticket.transaction do
        lock_key = Digest::SHA256.digest("v7a3:#{p.fetch('intent_key')}").unpack1("q>")
        ActiveRecord::Base.connection.exec_query("SELECT pg_advisory_xact_lock(#{Integer(lock_key)})")
        owners = Marlon::Ticket.where("extra_fields #>> '{project_tracking,key}' = ?", key).where.not(id: ticket.id)
        raise Rejected, "tracking identity already belongs to another ticket" if owners.exists?
        ticket.lock!
        data = ticket.extra_fields.to_h.deep_stringify_keys
        raise Rejected, "ticket tracking key mismatch" unless data.dig("project_tracking", "key") == key
        raise Rejected, "ticket already reserved" if data.dig("nevaeh", "execution_status").present? || data.dig("nevaeh", "work_item_id").present?
        existing = data["nevaeh_work_order"]
        if existing
          raise Rejected, "existing Work Order differs" unless existing == order
          result = :unchanged
        else
          data["nevaeh_work_order"] = order
          data["nevaeh_github_import"] = {
            "source" => "github_issue", "source_url" => p.fetch("inputs").fetch("source_url"),
            "source_fingerprint" => p.fetch("inputs").fetch("source_fingerprint"),
            "proposal_fingerprint" => p.fetch("proposal_fingerprint"),
            "import_status" => "inert"
          }
          ticket.update!(extra_fields: data)
          ticket.log!(action: "nevaeh_github_work_order_imported", detail: JSON.generate(data.fetch("nevaeh_github_import")))
          result = :attached
        end
      end
      result
    end

    def normalize_proposal!(raw)
      p = raw.is_a?(Hash) ? raw.deep_stringify_keys : nil
      raise Rejected, "invalid proposal" unless p
      fingerprint = p["proposal_fingerprint"]
      original = p.except("proposal_fingerprint")
      raise Rejected, "proposal fingerprint mismatch" unless fingerprint.is_a?(String) &&
        Digest::SHA256.hexdigest(JSON.generate(original)) == fingerprint
      raise Rejected, "wrong proposal type" unless p["work_type"] == "capability.build"
      input = p.fetch("inputs")
      raise Rejected, "unsupported source" unless input["source"] == "github_issue"
      raise Rejected, "unsupported repository" unless input["source_repository"] == GithubIssueContractV7a::REPOSITORY
      key = input.fetch("tracking_key")
      raise Rejected, "invalid identity" unless /\ASTUDIO-\d{3}\z/.match?(key) &&
        p["intent_key"] == "github:#{GithubIssueContractV7a::REPOSITORY}:#{key}" &&
        input["source_url"] == "https://github.com/#{GithubIssueContractV7a::REPOSITORY}/issues/#{input.fetch('source_number')}"
      policy = p.fetch("execution_policy")
      raise Rejected, "unsafe policy" unless policy == {
        "execution_enabled" => false, "production_allowed" => false,
        "requires_gatekeeper_authorization" => true, "requires_human_release_approval" => true
      }
      p
    rescue KeyError, TypeError, ArgumentError
      raise Rejected, "malformed proposal"
    end

    def to_order(proposal)
      {
        "version" => NevaehIntelligences::WorkOrder::VERSION,
        "work_type" => "build",
        "intent_key" => proposal.fetch("intent_key"),
        "objective" => proposal.fetch("objective"),
        "inputs" => proposal.fetch("inputs").merge("proposal_fingerprint" => proposal.fetch("proposal_fingerprint")),
        "acceptance_criteria" => proposal.fetch("acceptance_criteria"),
        "execution_policy" => {"environment" => "test", "approval" => "gatekeeper",
          "execution_enabled" => false, "production_allowed" => false,
          "requires_human_release_approval" => true}
      }
    end
  end
end
