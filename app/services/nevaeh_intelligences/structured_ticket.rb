# frozen_string_literal: true

module NevaehIntelligences
  module StructuredTicket
    class Invalid < WorkOrder::Invalid; end
    CAPABILITY = "ticket.structured.execute"
    HANDLER = "NevaehIntelligences::StructuredTicketWorker"
    ACTIONS = {
      "site.page.create" => {"label" => "Create website page", "fields" => %w[site_id title slug], "outputs" => %w[site_id page_id]},
      "site.section.add" => {"label" => "Add page section", "fields" => %w[site_id page_id kind data], "outputs" => %w[site_id page_id section_id]},
      "studio.project.create" => {"label" => "Create Studio project", "fields" => %w[name description], "outputs" => %w[project_id production_id default_scene_id]},
      "engineering.service.generate" => {"label" => "Implement reviewed metadata normalization service", "fields" => [], "outputs" => %w[path sha256 commit_sha branch]}
    }.freeze
    REF = /\A@([a-z][a-z0-9_]{0,39})\.([a-z][a-z0-9_]*)\z/
    module_function

    def compile(raw, bind_procedures: false)
      rows = raw.is_a?(Hash) ? raw.values : raw
      raise Invalid, "Add between 1 and 20 action sections" unless rows.is_a?(Array) && rows.length.between?(1, 20)
      seen = {}
      rows.map do |entry|
        raise Invalid, "Invalid action section" unless entry.is_a?(Hash)
        row = entry.deep_stringify_keys
        raise Invalid, "Unknown section fields" if (row.keys - %w[id action inputs depends_on procedure]).any?
        id = row.fetch("id", "").to_s
        raise Invalid, "Section IDs must be unique lowercase names" unless id.match?(/\A[a-z][a-z0-9_]{0,39}\z/) && !seen.key?(id)
        action = row.fetch("action", "")
        definition = ACTIONS[action] || raise(Invalid, "Unsupported action: #{action}")
        inputs = row.fetch("inputs", {})
        raise Invalid, "Section inputs must be an object" unless inputs.is_a?(Hash)
        inputs = inputs.deep_stringify_keys.reject { |_key, value| value == "" }
        raise Invalid, "Unknown inputs for #{action}" if (inputs.keys - definition.fetch("fields")).any?
        required = definition.fetch("fields") - %w[description]
        raise Invalid, "Missing inputs for #{action}: #{(required - inputs.keys).join(', ')}" if (required - inputs.keys).any?
        deps = row.fetch("depends_on", [])
        deps = deps.split(",").map(&:strip).reject(&:empty?) if deps.is_a?(String)
        raise Invalid, "Dependencies must be earlier section IDs" unless deps.is_a?(Array) && deps.all? { |dep| seen.key?(dep) }
        inputs.each do |key, value|
          if key.end_with?("_id")
            match = value.is_a?(String) && REF.match(value)
            if match
              previous = seen[match[1]] || raise(Invalid, "Reference must target an earlier section")
              raise Invalid, "Unknown referenced output" unless ACTIONS.fetch(previous).fetch("outputs").include?(match[2])
              deps |= [match[1]]
            else
              raise Invalid, "#{key} must be a positive ID or @section.output reference" unless value.to_s.match?(/\A[1-9][0-9]*\z/)
              inputs[key] = value.to_i
            end
          elsif key == "data"
            value = JSON.parse(value) if value.is_a?(String)
            raise Invalid, "Section data must be a bounded object" unless value.is_a?(Hash) && value.size <= 40 && JSON.generate(value).bytesize <= 16000
            inputs[key] = value.deep_stringify_keys
          else
            raise Invalid, "#{key} must be text" unless value.is_a?(String) && value.bytesize.between?(1, 4000)
          end
        end
        raise Invalid, "Use a URL slug such as about-us" if action == "site.page.create" && !inputs["slug"].to_s.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)
        seen[id] = action
        step = {"id" => id, "action" => action, "inputs" => inputs, "depends_on" => deps.uniq}
        if bind_procedures
          step["procedure"] = KnowledgeProcedures.bind!(action, row["procedure"])
        elsif row.key?("procedure")
          binding = row["procedure"]
          raise Invalid, "Invalid KB procedure reference" unless binding.is_a?(Hash) && binding.keys.sort == %w[article_id sha256] &&
            binding["article_id"].is_a?(Integer) && binding["article_id"].positive? && binding["sha256"].is_a?(String) && binding["sha256"].match?(/\A[0-9a-f]{64}\z/)
          step["procedure"] = binding
        end
        step
      end
    rescue JSON::ParserError
      raise Invalid, "Section data must be valid JSON"
    end

    def attach!(ticket:, actor:, sections:, automatic: false)
      raise Invalid, "Ticket submission permission required" unless actor&.persisted? && Ability.new(actor).can?(:create, Marlon::Ticket)
      raise Invalid, "Ticket execution permission required" if automatic && !Ability.new(actor).can?(:execute_nevaeh, ticket)
      compiled = compile(sections, bind_procedures: true)
      order = WorkOrder.template(work_type: "build", intent_key: CAPABILITY).merge(
        "objective" => ticket.title, "inputs" => {"sections" => compiled},
        "acceptance_criteria" => KnowledgeProcedures.criteria(compiled),
        "execution_policy" => {"environment" => Rails.env.to_s, "approval" => "gatekeeper"})
      ticket.with_lock do
        WorkOrder.attach!(ticket: ticket, attributes: order)
        fields = ticket.extra_fields.to_h.deep_stringify_keys
        fields["nevaeh_structured"] = {"version" => 1, "automatic" => automatic == true,
          "authorized_actor_id" => actor.id, "authorized_revision" => automatic ? TicketApproval.fingerprint(order) : nil,
          "steps" => {}}
        ticket.update!(extra_fields: fields)
        ticket.log!(action: "nevaeh_structured_ticket_saved", actor: actor, detail: {"sections" => compiled.map { |s| s.slice('id', 'action') }, "automatic" => automatic}.to_json)
      end
      order
    end

    def revise!(ticket:, actor:, sections:, automatic: false)
      raise Invalid, "Ticket execution permission required" unless actor&.persisted? && Ability.new(actor).can?(:execute_nevaeh, ticket)
      compiled = compile(sections, bind_procedures: true)
      ticket.with_lock do
        raise Invalid, "Resolved ticket cannot be revised" if ticket.status == "resolved"
        fields = ticket.extra_fields.to_h.deep_stringify_keys
        previous = WorkOrder.read!(ticket: ticket)
        raise Invalid, "Structured ticket required" unless previous["intent_key"] == CAPABILITY
        state = fields.fetch("nevaeh", {})
        if state["reservation_id"].present?
          items = DymondDispatch::WorkItem.where(subject_type: "Marlon::Ticket", subject_id: ticket.id, kind: CAPABILITY, correlation_id: state["reservation_id"]).to_a
          raise Invalid, "Stop and reconcile active work before revising" unless items.one? && %w[failed error dead].include?(items.first.status.to_s)
        end
        workflow = fields.fetch("nevaeh_structured")
        workflow.fetch("steps").each_key do |id|
          old = previous.fetch("inputs").fetch("sections").find { |step| step["id"] == id }
          raise Invalid, "Verified section #{id} must be preserved" unless compiled.find { |step| step["id"] == id } == old
        end
        order = previous.merge("inputs" => {"sections" => compiled}, "acceptance_criteria" => KnowledgeProcedures.criteria(compiled))
        WorkOrder.validate!(order)
        revision = TicketApproval.fingerprint(order)
        workflow.merge!("automatic" => automatic == true, "authorized_actor_id" => actor.id,
          "authorized_revision" => automatic ? revision : nil, "retry_count" => 0)
        state.merge!("work_order_sha256" => revision, "actor_id" => actor.id) if state["reservation_id"].present?
        fields["nevaeh_work_order"] = order
        fields["nevaeh_backlog"] = fields.fetch("nevaeh_backlog", {}).merge("status" => automatic ? "queued" : "awaiting_approval", "blockers" => [])
        ticket.update!(extra_fields: fields)
        ticket.log!(action: "nevaeh_structured_revision_saved", actor: actor, detail: {"previous_sha256" => TicketApproval.fingerprint(previous), "revision_sha256" => revision, "preserved_sections" => workflow.fetch("steps").keys, "automatic" => automatic}.to_json)
      end
      ProcessBacklogJob.perform_later(ticket_id: ticket.id) if automatic
    end

    def plan!(ticket:)
      raise Invalid, "Knowledge Base unavailable" unless defined?(DymondKb::Article) && DymondKb::Article.table_exists?
      ticket.with_lock do
        fields = ticket.extra_fields.to_h.deep_stringify_keys
        order = WorkOrder.read!(ticket: ticket)
        KnowledgeProcedures.validate_steps!(order.fetch("inputs").fetch("sections"))
        Array(fields["depends_on_ticket_ids"]).each do |id|
          dependency = id.is_a?(Integer) && id != ticket.id && Marlon::Ticket.find_by(id: id)
          raise Invalid, "Dependency ticket #{id} lacks verified resolution" unless dependency && dependency.status == "resolved" && dependency.extra_fields.to_h.dig("nevaeh", "execution_status") == "verified"
        end
        articles = ([CAPABILITY] + order.fetch("inputs").fetch("sections").map { |step| step.fetch("action") }).uniq.flat_map do |key|
          NevaehOrchestration::KnowledgeResolver.for(capability: key, additional_article_ids: fields.fetch("knowledge_article_ids", []))
        end.uniq(&:id)
        pinned_ids = order.fetch("inputs").fetch("sections").map { |step| step.fetch("procedure").fetch("article_id") }
        articles = (DymondKb::Article.where(id: pinned_ids).to_a + articles).uniq(&:id)
        capabilities = NevaehCapability.order(:id).map do |record|
          {"slug" => record.slug, "enabled" => record.enabled?, "handler" => record.handler,
            "gatekeeper_capability" => record.gatekeeper_capability, "updated_at" => record.updated_at&.iso8601(6)}
        end
        plan = GithubDevelopmentPlanV7a.from_native_ticket(ticket: ticket, knowledge_article_ids: articles.map(&:id),
          capability_snapshot: capabilities, required_capability: CAPABILITY,
          source_evidence: {"registered_actions" => order.fetch("inputs").fetch("sections").map { |step| step.slice("id", "action", "depends_on") }})
        state = fields.fetch("nevaeh_backlog", {})
        state.merge!("status" => "executing", "required_capability" => CAPABILITY, "engineering_plan" => plan,
          "knowledge_article_ids" => articles.map(&:id), "blockers" => [], "updated_at" => Time.current.iso8601)
        fields["nevaeh_backlog"] = state
        ticket.update!(extra_fields: fields)
      end
    end

    def registered!
      record = NevaehCapability.find_or_initialize_by(slug: CAPABILITY)
      if record.new_record?
        record.assign_attributes(name: "Structured ticket execution", domain: "support", intent_name: "execute_structured_ticket",
          handler: HANDLER, queue: ENV.fetch("NEVAEH_STRUCTURED_QUEUE", "default"), priority: 5,
          subject_type: "Marlon::Ticket", gatekeeper_capability: CAPABILITY,
          event_types: ["ticket.structured.requested"], enabled: true, expected_outcome: {"verified" => true})
        record.save!
      end
      intelligence = NevaehIntelligence.find_or_initialize_by(intent_key: CAPABILITY)
      if intelligence.new_record?
        intelligence.assign_attributes(name: "Complete structured ticket", nevaeh_capability: record, target_model: "Marlon::Ticket",
          operation: "execute", status: "published", execution_mode: "async", instructions: {"action" => "execute"})
        intelligence.save!
      end
      record
    end
  end
end
