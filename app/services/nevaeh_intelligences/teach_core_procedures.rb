# frozen_string_literal: true
require "json"
module NevaehIntelligences
  # Release-authored lessons for already implemented actions. Never overwrite an
  # instance operator's amended, withdrawn, or disabled lesson on a later deploy.
  module TeachCoreProcedures
    module_function

    def call(root: Rails.root)
      rows = JSON.parse(File.read(File.join(root, "config/nevaeh/procedures/core.json")))
      rows.map do |row|
        key = row.fetch("key")
        columns = DymondKb::Article.column_names
        identity = columns.include?("article_id") ? {article_id: key} : {slug: key}
        existing = DymondKb::Article.find_by(identity)
        next existing if existing
        contract = row.fetch("contract")
        # Validate a lesson before it can become a selectable request.
        draft = Struct.new(:id, :metadata, :body).new(1, {KnowledgeProcedures::KEY => contract}, row.fetch("body"))
        KnowledgeProcedures.definition(draft)
        Gatekeeper::LessonService.record!(key: key, title: contract.fetch("label"), capability: contract.fetch("action"),
          symptom: "Supported request: #{contract.fetch('label')}", cause: "Registered Lightek functionality",
          remediation: row.fetch("body"), verification: contract.fetch("acceptance_criteria").join("\n"),
          metadata: {"nevaeh_capability" => contract.fetch("action"), KnowledgeProcedures::KEY => contract,
            "source" => "reviewed_release_procedure", "verification_policy" => "Run the registered verifier for every execution; lesson availability is not execution evidence"})
      end
    end
  end
end
