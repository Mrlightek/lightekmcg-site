# frozen_string_literal: true
module NevaehIntelligences
  module LessonDistribution
    module_function

    def export!(ids:, actor:)
      Gatekeeper::Fleet::Rollouts.authorize!(actor)
      ids = Array(ids).reject(&:blank?).map { |id| Integer(id.to_s, 10) }.uniq
      return {} if ids.empty?
      raise KnowledgeProcedures::Invalid, "Choose at most 50 taught lessons" if ids.size > 50
      available = KnowledgeProcedures.available.values.index_by { |row| row.fetch("procedure").fetch("article_id") }
      lessons = ids.sort.map do |id|
        definition = available.fetch(id) { raise KnowledgeProcedures::Invalid, "Lesson #{id} is unavailable" }
        article = DymondKb::Article.find(id)
        revision = definition.fetch("procedure").fetch("sha256")
        proof = article.metadata.to_h.fetch("nevaeh_verified_executions", {}).values.find { |value| value["procedure_sha256"] == revision }
        raise KnowledgeProcedures::Invalid, "Lesson #{id} has no verified execution of its current revision" unless proof
        {"key" => article.respond_to?(:article_id) ? article.article_id : article.slug, "title" => article.title,
          "body" => article.body, "contract" => article.metadata.fetch("nevaeh_procedure"), "sha256" => revision,
          "previous_sha256" => article.metadata.fetch("nevaeh_lesson_revisions", []).last.to_h["previous_procedure_sha256"]}
      end
      bundle = {"version" => 1, "lessons" => lessons}
      raise KnowledgeProcedures::Invalid, "Knowledge bundle exceeds 256 KB" if JSON.generate(bundle).bytesize > 256000
      bundle.merge("sha256" => TicketApproval.fingerprint(bundle))
    end

    def import!(bundle)
      value = bundle.to_h.deep_stringify_keys
      raise KnowledgeProcedures::Invalid, "Invalid knowledge bundle" unless value["version"] == 1 && value["lessons"].is_a?(Array) && value["lessons"].size.between?(1, 50) &&
        JSON.generate(value).bytesize <= 256000 && value["sha256"] == TicketApproval.fingerprint(value.except("sha256"))
      DymondKb::Article.transaction do
        value.fetch("lessons").sort_by { |entry| entry.fetch("key") }.each do |lesson|
          key = lesson.fetch("key")
          raise KnowledgeProcedures::Invalid, "Invalid lesson identity" unless key.is_a?(String) && key.match?(/\A[a-z0-9][a-z0-9_-]{0,159}\z/)
          draft = Struct.new(:id, :metadata, :body).new(1, {"nevaeh_procedure" => lesson.fetch("contract")}, lesson.fetch("body"))
          definition = KnowledgeProcedures.definition(draft)
          raise KnowledgeProcedures::Invalid, "Lesson revision mismatch" unless definition.fetch("procedure").fetch("sha256") == lesson.fetch("sha256")
          identity = DymondKb::Article.column_names.include?("article_id") ? {article_id: key} : {slug: key}
          article = DymondKb::Article.find_by(identity)
          if article
            article.lock!
            local = KnowledgeProcedures.definition(article).fetch("procedure").fetch("sha256")
            next if local == lesson.fetch("sha256")
            raise KnowledgeProcedures::Invalid, "Instance lesson #{key} differs; review its local changes before replacing it" unless local == lesson["previous_sha256"]
          else
            # Use the existing KB service for topic/model requirements.
            article = Gatekeeper::LessonService.record!(key: key, title: lesson.fetch("title"), capability: definition.fetch("action"),
              symptom: "Centrally distributed procedure", cause: "Verified support solution", remediation: lesson.fetch("body"),
              verification: definition.fetch("acceptance_criteria").join("\n"))
          end
          metadata = article.metadata.to_h.merge("nevaeh_procedure" => lesson.fetch("contract"),
            "central_distribution" => {"bundle_sha256" => value.fetch("sha256"), "source_revision" => lesson.fetch("sha256"), "applied_at" => Time.current.iso8601})
          article.update!(title: lesson.fetch("title"), body: lesson.fetch("body"), metadata: metadata)
        end
      end
      {"sha256" => value.fetch("sha256"), "lessons" => value.fetch("lessons").size}
    end
  end
end
