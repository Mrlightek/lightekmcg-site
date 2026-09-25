module Gatekeeper
  class KnowledgeService
    MAX_MATCHES = 5

    def self.for_capability(capability)
      return DymondKb::Article.none unless DymondKb::Article.table_exists?

      DymondKb::Article
        .where(article_type: "troubleshooting")
        .where("metadata ->> 'gatekeeper_capability' = ?", capability.to_s)
        .ordered
    end

    def self.find_for_failure(operation:, error:)
      direct = for_capability(operation.capability).to_a
      return direct.first(MAX_MATCHES) if direct.any?

      query = [operation.capability.to_s.tr("_", " "), error&.message.to_s]
        .reject(&:blank?)
        .join(" ")
        .squish
        .first(240)

      return [] if query.blank?

      DymondKb::Article
        .where(article_type: "troubleshooting")
        .search(query)
        .ordered
        .limit(MAX_MATCHES)
        .to_a
    rescue StandardError => e
      Rails.logger.warn("[Gatekeeper::KnowledgeService] KB lookup failed: #{e.class}: #{e.message}")
      []
    end
  end
end
