# frozen_string_literal: true

module NevaehOrchestration
  class KnowledgeResolver
    MAX_MATCHES = 5

    def self.for(capability:, additional_article_ids: [])
      new(
        capability: capability,
        additional_article_ids: additional_article_ids
      ).call
    end

    def initialize(capability:, additional_article_ids: [])
      @capability = capability.to_s
      @additional_article_ids = Array(additional_article_ids).compact
    end

    def call
      return [] unless defined?(DymondKb::Article)
      return [] unless DymondKb::Article.table_exists?

      matches = direct_matches.to_a

      matches += explicit_matches if additional_article_ids.any?

      matches
        .uniq { |article| article.id }
        .first(MAX_MATCHES)
    rescue StandardError => error
      Rails.logger.warn(
        "[Nevaeh::KnowledgeResolver] lookup failed " \
        "capability=#{capability.inspect} " \
        "#{error.class}: #{error.message}"
      )

      []
    end

    private

    attr_reader :capability, :additional_article_ids

    def direct_matches
      DymondKb::Article
        .where(article_type: %w[troubleshooting guide reference])
        .where(
          <<~SQL.squish,
            metadata ->> 'nevaeh_capability' = :capability
            OR metadata ->> 'gatekeeper_capability' = :capability
            OR metadata ->> 'capability' = :capability
          SQL
          capability: capability
        )
        .order(:sort_order, :id)
        .limit(MAX_MATCHES)
    end

    def explicit_matches
      relation = DymondKb::Article.all

      if DymondKb::Article.column_names.include?("article_id")
        relation.where(article_id: additional_article_ids)
      else
        relation.where(id: additional_article_ids)
      end.to_a
    end
  end
end
