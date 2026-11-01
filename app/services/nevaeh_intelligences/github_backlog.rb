# frozen_string_literal: true
require "digest"
require "json"
module NevaehIntelligences
  module GithubBacklog
    REPOSITORY = GithubIssueContractV7a::REPOSITORY
    IMPORT_CAPABILITY = "github.tickets.import"
    module_function

    def authorize_import!(actor:)
      raise WorkOrder::Invalid, "GitHub intake requires an authorized operator" unless actor&.persisted? && Ability.new(actor).can?(:execute_nevaeh, Marlon::Ticket)
      capability = NevaehCapability.find_or_initialize_by(slug: IMPORT_CAPABILITY)
      if capability.new_record?
        capability.assign_attributes(name: "Import GitHub support requests", domain: "support", intent_name: "import_github_issues",
          handler: "NevaehIntelligences::SyncGithubIssuesJob", queue: "default", priority: 5,
          gatekeeper_capability: IMPORT_CAPABILITY, enabled: true)
        capability.save!
      end
      raise WorkOrder::Invalid, "GitHub intake capability has a conflicting handler" unless capability.handler == "NevaehIntelligences::SyncGithubIssuesJob" && capability.gatekeeper_capability == IMPORT_CAPABILITY
      Gatekeeper.authorize_capability!(capability: IMPORT_CAPABILITY, context: {"actor" => {"type" => "User", "id" => actor.id}})
    end

    def repository_evidence(source)
      path = Rails.root.join("config/project_tracking/lightek_studio.json")
      key = source.fetch("title")[/\A\[(STUDIO-\d{3})\]/, 1]
      item = JSON.parse(File.read(path)).fetch("items").find { |entry| entry["key"] == key } if key
      {"tracking_key" => key, "tracking_status" => item&.fetch("status"),
        "tracking_evidence" => item&.fetch("evidence", []), "tracking_source_sha256" => Digest::SHA256.file(path).hexdigest,
        "implementation_verification" => "requires_acceptance_checks"}.compact
    end

    def normalize(raw)
      value = raw.to_h.deep_stringify_keys
      number = Integer(value["number"] || value["issue_number"])
      raise WorkOrder::Invalid, "Invalid GitHub issue identity" unless number.positive? && !value.key?("pull_request") &&
        (value["html_url"] || value["url"]) == "https://github.com/#{REPOSITORY}/issues/#{number}"
      raise WorkOrder::Invalid, "Issue must be open" unless value["state"] == "open"
      title, body = value.fetch("title"), value.fetch("body", "").to_s
      raise WorkOrder::Invalid, "Invalid GitHub issue content" unless title.is_a?(String) && title.bytesize.between?(1, 1000) && body.bytesize <= 128000
      issue = {"repository" => REPOSITORY, "number" => number, "url" => "https://github.com/#{REPOSITORY}/issues/#{number}",
        "title" => title, "body" => body, "updated_at" => value["updated_at"], "state" => "open"}
      issue["source_sha256"] = Digest::SHA256.hexdigest(JSON.generate(issue.slice("repository", "number", "title", "body")))
      issue
    rescue ArgumentError, TypeError, KeyError
      raise WorkOrder::Invalid, "Malformed GitHub issue"
    end

    def relation
      Marlon::Ticket.where("extra_fields #>> '{nevaeh_github,repository}' = ?", REPOSITORY)
    end

    def import!(raw, actor: nil)
      source = normalize(raw)
      ticket = nil
      Marlon::Ticket.transaction do
        lock = Digest::SHA256.digest("nevaeh:github:#{REPOSITORY}:#{source['number']}").unpack1("q>")
        ActiveRecord::Base.connection.exec_query("SELECT pg_advisory_xact_lock(#{Integer(lock)})")
        matches = relation.where("extra_fields #>> '{nevaeh_github,number}' = ?", source["number"].to_s).to_a
        # Reuse a previously imported canonical Studio ticket rather than cloning it.
        if matches.empty? && (key = source["title"][/\A\[(STUDIO-\d{3})\]/, 1])
          matches = Marlon::Ticket.where("extra_fields #>> '{project_tracking,key}' = ?", key).select do |row|
            row.extra_fields.to_h.dig("nevaeh_github_import", "source_url") == source["url"]
          end
        end
        raise WorkOrder::Invalid, "Multiple tickets claim GitHub issue #{source['number']}; reconcile duplicates" if matches.size > 1
        ticket = matches.first || Marlon::Ticket.create!(title: source["title"], description: source["body"], category: "technical",
          priority: source["body"].include?("**Priority:** P0") ? "high" : "medium", urgency: 5, status: "open", submitted_by: actor)
        ticket.lock!
        fields = ticket.extra_fields.to_h.deep_stringify_keys
        previous = fields["nevaeh_github"]
        return ticket if previous && previous["source_sha256"] == source["source_sha256"]
        source["imported_at"] = Time.current.iso8601
        fields["nevaeh_github"] = source
        fields["project_tracking"] ||= {"key" => source["title"][/\A\[(STUDIO-\d{3})\]/, 1]}.compact
        fields["nevaeh_github_revisions"] = (fields.fetch("nevaeh_github_revisions", []) + [previous].compact).last(20)
        reserved = fields.dig("nevaeh", "reservation_id").present?
        if reserved || ticket.status == "resolved"
          fields["nevaeh_github"]["revision_requires_review"] = true
          ticket.update!(extra_fields: fields)
          ticket.log!(action: "nevaeh_github_revision_awaiting_review", detail: source.slice("number", "source_sha256").to_json)
          return ticket
        end
        fields["nevaeh_work_order_history"] = (fields.fetch("nevaeh_work_order_history", []) + [fields["nevaeh_work_order"]].compact).last(20)
        fields.delete("nevaeh_work_order")
        ticket.update!(extra_fields: fields)
        order = WorkOrder.template(work_type: "build", intent_key: "kb.procedure.required").merge("objective" => source["title"],
          "inputs" => source.slice("repository", "number", "url", "source_sha256"),
          "acceptance_criteria" => ["Teach and register a procedure covering the complete request in #{source['url']}", "Run the procedure's regression and acceptance checks", "Preserve verified implementation and KB evidence before closing the GitHub issue"],
          "execution_policy" => {"environment" => Rails.env.to_s, "approval" => "gatekeeper"})
        WorkOrder.attach!(ticket: ticket, attributes: order)
        ticket.log!(action: "nevaeh_github_issue_imported", detail: source.slice("repository", "number", "url", "source_sha256").to_json, actor: actor)
      end
      ticket
    end

    def process!(ticket:)
      fields = ticket.reload.extra_fields.to_h.deep_stringify_keys
      source = fields.fetch("nevaeh_github")
      # Issue prose never grants an execution capability. An operator teaches a
      # complete recipe, then binds the actual source revision to its work order.
      order = WorkOrder.read!(ticket: ticket)
      if order["intent_key"] == StructuredTicket::CAPABILITY
        steps = order.fetch("inputs").fetch("sections")
        binding = fields["nevaeh_github_authorization"]
        if binding == {"source_sha256" => source["source_sha256"], "work_order_sha256" => TicketApproval.fingerprint(order)} && !source["revision_requires_review"]
          KnowledgeProcedures.validate_steps!(steps)
          return nil
        end
      end
      repository = repository_evidence(source)
      blockers = ["This GitHub source revision has no approved KB procedure binding; teach its complete implementation and acceptance checks, then save a reviewed work order"]
      blockers << "The repository roadmap marks this feature done; verify the existing implementation and teach its acceptance procedure before closing" if repository["tracking_status"] == "done"
      blockers << "GitHub issue changed after authorization; review its new revision" if source["revision_requires_review"]
      ticket.with_lock do
        fields = ticket.extra_fields.to_h.deep_stringify_keys
        order = WorkOrder.read!(ticket: ticket)
        articles = NevaehOrchestration::KnowledgeResolver.for(capability: "kb.procedure.required", additional_article_ids: fields.fetch("knowledge_article_ids", []))
        query = source.fetch("title").sub(/\A\[STUDIO-\d{3}\]\s*/, "").first(240)
        articles = (articles + DymondKb::Article.search(query).ordered.limit(5).to_a).uniq(&:id)
        snapshot = NevaehCapability.order(:id).map { |row| {"slug" => row.slug, "enabled" => row.enabled?, "handler" => row.handler} }
        plan = GithubDevelopmentPlanV7a.from_native_ticket(ticket: ticket, knowledge_article_ids: articles.map(&:id), capability_snapshot: snapshot,
          source_evidence: source.slice("repository", "number", "url", "source_sha256").merge("repository_inspection" => repository))
        fields["nevaeh_backlog"] = fields.fetch("nevaeh_backlog", {}).merge("status" => "escalated", "classification" => repository["tracking_status"] == "done" ? "verification" : "engineering",
          "engineering_plan" => plan, "knowledge_article_ids" => articles.map(&:id), "blockers" => blockers,
          "implementation_verified" => false, "updated_at" => Time.current.iso8601)
        ticket.update!(extra_fields: fields)
      end
      NevaehOrchestration::Escalation.knowledge_gap!(ticket: ticket, reason: blockers.join("; "))
      "escalated"
    end
  end
end
