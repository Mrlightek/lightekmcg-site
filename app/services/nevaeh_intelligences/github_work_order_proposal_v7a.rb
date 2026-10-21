# frozen_string_literal: true

require "digest"
require "json"

module NevaehIntelligences
  # Pure data proposal for existing WorkOrder API. Does not persist, authorize or dispatch.
  # Explicitly separate issue identity from user-controlled issue description.
  module GithubWorkOrderProposalV7a
    class ProposalError < StandardError; end
    WORK_TYPE = "capability.build".freeze
    MAX_OBJECTIVE_BYTES = 8192

    module_function

    def from_issue(issue, roadmap:)
      contract = GithubIssueContractV7a.from_issue(issue, roadmap: roadmap)
      from_contract(contract)
    end

    def from_contract(raw)
      c = raw.is_a?(Hash) ? raw.transform_keys(&:to_s) : nil
      raise ProposalError, "invalid normalized contract" unless c
      raise ProposalError, "unsupported source" unless c["source"] == "github_issue"
      raise ProposalError, "unsupported repository" unless c["repository"] == GithubIssueContractV7a::REPOSITORY
      raise ProposalError, "contract is executable" unless c["requires_authorization"] == true && c["execution_enabled"] == false
      raise ProposalError, "invalid fingerprint" unless c["fingerprint"].is_a?(String) && /\A[0-9a-f]{64}\z/.match?(c["fingerprint"])
      original = c.reject { |k, _| k == "fingerprint" }
      raise ProposalError, "contract tampered" unless Digest::SHA256.hexdigest(JSON.generate(original)) == c["fingerprint"]
      key = c.fetch("tracking_key")
      raise ProposalError, "invalid tracking key" unless /\ASTUDIO-\d{3}\z/.match?(key)
      number = c.fetch("source_number")
      raise ProposalError, "invalid issue number" unless number.is_a?(Integer) && number.positive?
      url = "https://github.com/#{GithubIssueContractV7a::REPOSITORY}/issues/#{number}"
      raise ProposalError, "issue URL mismatch" unless c["source_url"] == url
      objective = c.fetch("objective")
      raise ProposalError, "objective invalid" unless objective.is_a?(String) && !objective.strip.empty? && objective.bytesize <= MAX_OBJECTIVE_BYTES

      # This is an inert parameter contract. The WorkOrder persistence/dispatch API
      # is intentionally not called until its local shape is independently verified.
      proposal = {
        "work_type" => WORK_TYPE,
        "intent_key" => "github:#{GithubIssueContractV7a::REPOSITORY}:#{key}",
        "objective" => objective,
        "inputs" => {
          "source" => "github_issue",
          "source_repository" => c.fetch("repository"),
          "source_url" => url,
          "source_number" => number,
          "tracking_key" => key,
          "source_fingerprint" => c.fetch("fingerprint"),
          "requested_feature" => c.fetch("title"),
          "priority" => c.fetch("priority"),
          "roadmap_phase" => c.fetch("phase"),
          "roadmap_area" => c.fetch("area"),
          "effort" => c.fetch("effort")
        },
        "acceptance_criteria" => [
          "Implementation artifacts trace to #{key} and GitHub issue #{number}",
          "Relevant tests must pass in an isolated non-production workspace",
          "Nevaeh must attach verification evidence before marking the ticket complete"
        ],
        "execution_policy" => {
          "execution_enabled" => false,
          "production_allowed" => false,
          "requires_gatekeeper_authorization" => true,
          "requires_human_release_approval" => true
        }
      }
      proposal["proposal_fingerprint"] = Digest::SHA256.hexdigest(JSON.generate(proposal))
      deep_freeze(proposal)
    rescue KeyError, TypeError, ArgumentError => e
      raise ProposalError, "invalid proposal inputs: #{e.class}"
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
