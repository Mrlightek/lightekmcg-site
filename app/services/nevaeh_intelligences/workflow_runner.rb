# frozen_string_literal: true
module NevaehIntelligences
  module WorkflowRunner
    module_function

    def request!(workflow:, actor:, request_key:)
      raise WorkOrder::Invalid, "Workflow administration required" unless actor&.persisted? && Ability.new(actor).can?(:manage, NevaehWorkflow)
      raise WorkOrder::Invalid, "Request key required" unless request_key.to_s.match?(/\A[a-zA-Z0-9:_-]{8,100}\z/)
      workflow.with_lock do
        raise WorkOrder::Invalid, "Activate this worker before running it" unless workflow.status == "active"
        workflow.runs.find_or_create_by!(request_key: request_key) do |run|
          run.actor = actor
          run.snapshot = {"name" => workflow.name, "description" => workflow.description, "sections" => workflow.sections}
        end
      end
    end

    def materialize!(run)
      run.with_lock do
        return run.ticket if run.ticket_id
        actor = run.actor.reload
        raise WorkOrder::Invalid, "Operator permission revoked" unless Ability.new(actor).can?(:manage, NevaehWorkflow)
        ticket = Marlon::Ticket.create!(title: run.snapshot.fetch("name"), description: run.snapshot["description"].presence || "Nevaeh worker run ##{run.id}",
          category: Marlon::TicketCategories.ids.first, priority: "medium", urgency: 5, status: "open", submitted_by: actor)
        StructuredTicket.attach!(ticket: ticket, actor: actor, sections: run.snapshot.fetch("sections"), automatic: true)
        ticket.log!(action: "nevaeh_workflow_requested", actor: actor, detail: {workflow_id: run.nevaeh_workflow_id, run_id: run.id}.to_json)
        run.update!(ticket: ticket)
        ticket
      end
    end

    def tick!
      now = Time.current
      NevaehWorkflow.where(status: "active").where("next_run_at <= ?", now).order(:next_run_at).limit(100).each do |workflow|
        workflow.with_lock do
          next unless workflow.status == "active" && workflow.next_run_at && workflow.next_run_at <= now && workflow.interval_minutes
          # A durable unique slot and row lock make competing scheduler sweeps idempotent.
          request!(workflow: workflow, actor: workflow.creator, request_key: "schedule:#{workflow.next_run_at.to_i}")
          workflow.update!(next_run_at: now + workflow.interval_minutes.minutes)
        rescue WorkOrder::Invalid => error
          workflow.update!(status: "paused")
          Rails.logger.warn("Nevaeh schedule #{workflow.id} paused: #{error.message}")
        end
      end
      # Also recovers a process that committed the run before queue submission failed.
      NevaehWorkflowRun.where(status: "queued").order(:id).limit(100).pluck(:id).each { |id| WorkflowRunJob.perform_later(id) }
    end
  end
end
