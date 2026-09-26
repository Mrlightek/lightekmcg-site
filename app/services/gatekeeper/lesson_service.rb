module Gatekeeper
  class LessonService
    class KnowledgeBaseUnavailable < StandardError; end

    def self.record!(key:, title:, capability:, symptom:, cause:, remediation:, verification:, metadata: {})
      new(
        key: key,
        title: title,
        capability: capability,
        symptom: symptom,
        cause: cause,
        remediation: remediation,
        verification: verification,
        metadata: metadata
      ).record!
    end

    def initialize(key:, title:, capability:, symptom:, cause:, remediation:, verification:, metadata:)
      @key = key.to_s
      @title = title.to_s
      @capability = capability.to_s
      @symptom = symptom.to_s
      @cause = cause.to_s
      @remediation = remediation.to_s
      @verification = verification.to_s
      @metadata = metadata.to_h
    end

    def record!
      raise KnowledgeBaseUnavailable, "DymondKb::Article is unavailable" unless defined?(DymondKb::Article)
      raise KnowledgeBaseUnavailable, "dymond_kb_articles table is unavailable" unless DymondKb::Article.table_exists?

      article = lookup_article
      attrs = build_attributes(article)
      article.assign_attributes(attrs)
      assign_topic_if_required!(article)
      article.save!

      Rails.logger.info("[Gatekeeper::LessonService] Recorded lesson #{key} as KB article #{article_identifier(article)}")
      article
    end

    private

    attr_reader :key, :title, :capability, :symptom, :cause, :remediation, :verification, :metadata

    def lookup_article
      columns = DymondKb::Article.column_names

      if columns.include?("article_id")
        DymondKb::Article.find_or_initialize_by(article_id: key)
      elsif columns.include?("slug")
        DymondKb::Article.find_or_initialize_by(slug: key)
      else
        DymondKb::Article.find_or_initialize_by(title: title)
      end
    end

    def assign_topic_if_required!(article)
      return unless article.respond_to?(:topic=)
      return if article.respond_to?(:topic) && article.topic.present?
      return unless defined?(DymondKb::Topic)

      topic = find_existing_topic

      unless topic
        raise KnowledgeBaseUnavailable,
              "DymondKb::Article requires a Topic, but no existing DymondKb::Topic could be selected"
      end

      article.topic = topic
    end

    def find_existing_topic
      scope = DymondKb::Topic.all
      columns = DymondKb::Topic.column_names

      if columns.include?("slug")
        topic = scope.where(slug: %w[troubleshooting operations gatekeeper]).first
        return topic if topic
      end

      %w[name title label].each do |column|
        next unless columns.include?(column)

        topic = scope
          .where("#{column} ILIKE ? OR #{column} ILIKE ? OR #{column} ILIKE ?",
                 "%troubleshoot%", "%operation%", "%gatekeeper%")
          .first
        return topic if topic
      end

      scope.order(:id).first
    end

    def build_attributes(article)
      columns = article.class.column_names
      attrs = {}

      attrs[:article_id] = key if columns.include?("article_id")
      attrs[:slug] = key.tr("_", "-") if columns.include?("slug")
      attrs[:title] = title if columns.include?("title")
      attrs[:article_type] = "troubleshooting" if columns.include?("article_type")
      attrs[:excerpt] = symptom.first(240) if columns.include?("excerpt")
      attrs[:body] = body if columns.include?("body")
      attrs[:read_minutes] = 3 if columns.include?("read_minutes")
      attrs[:featured] = false if columns.include?("featured")
      attrs[:metadata] = lesson_metadata if columns.include?("metadata")

      attrs
    end

    def body
      <<~TEXT
        ## Symptom

        #{symptom}

        ## Root Cause

        #{cause}

        ## Remediation

        #{remediation}

        ## Verification

        #{verification}

        ## Operational Lesson

        A presentation shell is also a controller contract. When a host application renders a DymondDash layout from a non-DymondDash controller, the controller must inherit from DymondDash::ApplicationController (or otherwise implement the complete contract expected by the layout). Do not copy individual helper methods as a workaround.

        ## Production Diagnostics

        For the Lightek Apache/Passenger deployment, Rails/Passenger request exceptions are available in:
        /var/log/apache2/lightekmcg-site-error.log
      TEXT
    end

    def lesson_metadata
      {
        "source" => "gatekeeper",
        "lesson_key" => key,
        "gatekeeper_capability" => capability,
        "incident_class" => "controller_shell_contract_mismatch",
        "failure_signature" => "NameError: undefined local variable or method `account_plan'",
        "component" => "dymond_dash",
        "affected_feature" => "susu",
        "auto_executable" => false,
        "verification_capability" => "verify_dymond_dash_controller_contract",
        "production_log_path" => "/var/log/apache2/lightekmcg-site-error.log",
        "known_remediation" => "inherit DymondDash::ApplicationController when rendering the DymondDash shell",
        "learned_from_human_intervention" => true
      }.merge(metadata.stringify_keys)
    end

    def article_identifier(article)
      if article.respond_to?(:article_id) && article.article_id.present?
        article.article_id
      elsif article.respond_to?(:slug) && article.slug.present?
        article.slug
      else
        article.id
      end
    end
  end
end
