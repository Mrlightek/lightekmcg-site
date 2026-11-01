# frozen_string_literal: true
require "digest"
require "json"

module NevaehIntelligences
  # KB records describe supported requests; Ruby actions remain the implementation
  # boundary. Article prose is never evaluated as code or a shell command.
  module KnowledgeProcedures
    class Invalid < WorkOrder::Invalid; end
    KEY = "nevaeh_procedure"
    module_function

    def canonical(value)
      case value
      when Hash then value.keys.sort.to_h { |key| [key, canonical(value.fetch(key))] }
      when Array then value.map { |entry| canonical(entry) }
      else value
      end
    end

    def definition(article)
      contract = article.metadata.to_h[KEY]
      raise Invalid, "KB article has no available request procedure" unless contract.is_a?(Hash) && contract["status"] == "available"
      action = contract["action"]
      executor = StructuredTicket::ACTIONS[action]
      raise Invalid, "KB procedure has no registered executor and verifier" unless executor
      worker = StructuredActions.worker_for(action)
      raise Invalid, "KB procedure must bind its registered backend worker" unless contract["worker"] == worker.name && worker.respond_to?(:perform) && worker.respond_to?(:verify!)
      raise Invalid, "Unsupported procedure contract" unless contract["version"] == 1
      raise Invalid, "Procedure label is required" unless contract["label"].is_a?(String) && contract["label"].strip.length.between?(1, 160)
      schema = contract["inputs"]
      raise Invalid, "KB inputs must match the implemented action" unless schema.is_a?(Hash) && schema.keys.sort == executor.fetch("fields").sort
      schema.each do |name, field|
        expected = name.end_with?("_id") ? "record_id" : (name == "data" ? "object" : "text")
        raise Invalid, "Unsupported KB input #{name}" unless field.is_a?(Hash) && field["type"] == expected &&
          field["required"] == (name != "description") && field["label"].is_a?(String) && field["label"].strip.length.between?(1, 120)
      end
      checks = contract["acceptance_criteria"]
      raise Invalid, "Procedure acceptance criteria are required" unless checks.is_a?(Array) && checks.length.between?(1, 20) &&
        checks.all? { |check| check.is_a?(String) && check.strip.length.between?(1, 1000) }
      raise Invalid, "Procedure verification must use the registered action verifier" unless contract["verifier"] == action
      digest = Digest::SHA256.hexdigest(JSON.generate(canonical({"contract" => contract, "body" => article.body.to_s})))
      {"action" => action, "worker" => worker.name, "label" => contract["label"], "fields" => schema.keys,
        "inputs" => schema, "outputs" => executor.fetch("outputs"), "acceptance_criteria" => checks,
        "procedure" => {"article_id" => article.id, "sha256" => digest}}
    end

    def available
      return {} unless defined?(DymondKb::Article) && DymondKb::Article.table_exists?
      capability = NevaehCapability.find_by(slug: StructuredTicket::CAPABILITY)
      return {} unless capability&.enabled? && capability.handler == StructuredTicket::HANDLER &&
        capability.gatekeeper_capability == StructuredTicket::CAPABILITY
      rows = DymondKb::Article.where("metadata ->> 'nevaeh_procedure' IS NOT NULL").order(:id)
      candidates = rows.filter_map do |article|
        definition(article)
      rescue Invalid
        nil # Draft, withdrawn, and malformed procedures cannot advertise requests.
      end
      candidates.group_by { |row| row.fetch("action") }.each_with_object({}) do |(action, matches), result|
        result[action] = matches.first if matches.one? # Ambiguous owners require KB review.
      end
    end

    def fetch!(action)
      available.fetch(action) { raise Invalid, "No available KB procedure for #{action}; review the Knowledge Base before requesting this work" }
    end

    def bind!(action, supplied = nil)
      binding = fetch!(action).fetch("procedure")
      if supplied.is_a?(Hash) && supplied["article_id"].to_s.match?(/\A[1-9][0-9]*\z/)
        supplied = supplied.merge("article_id" => supplied["article_id"].to_i)
      end
      raise Invalid, "KB procedure changed; review the current lesson and save a new revision" if supplied && supplied != binding
      binding
    end

    def validate_steps!(steps)
      steps.each do |step|
        raise Invalid, "This work predates KB-bound requests; review and save its procedure before execution" unless step["procedure"]
        bind!(step.fetch("action"), step.fetch("procedure"))
      end
      true
    end

    def criteria(steps)
      steps.flat_map { |step| fetch!(step.fetch("action")).fetch("acceptance_criteria").map { |check| "#{step.fetch('id')}: #{check}" } }
    end

    def record_verification!(ticket:, steps:, completed:, solution_article:)
      steps.group_by { |step| step.fetch("procedure").fetch("article_id") }.sort.each do |article_id, matches|
        article = DymondKb::Article.find(article_id)
        article.with_lock do
          matches.each do |step|
            raise Invalid, "Lesson changed before recording acceptance" unless definition(article).fetch("procedure") == step.fetch("procedure")
            raise Invalid, "Only verified execution can teach a lesson" unless completed.dig(step.fetch("id"), "status") == "verified"
          end
          metadata = article.metadata.to_h.deep_stringify_keys
          history = metadata.fetch("nevaeh_verified_executions", {})
          history[ticket.id.to_s] = {"solution_article_id" => solution_article.id, "verified_at" => Time.current.iso8601,
            "evidence_sha256" => Digest::SHA256.hexdigest(JSON.generate(canonical(completed)))}
          metadata["nevaeh_verified_executions"] = history.to_a.last(100).to_h
          article.update!(metadata: metadata)
        end
      end
    end
  end
end
