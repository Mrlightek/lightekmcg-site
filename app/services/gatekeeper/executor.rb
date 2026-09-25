module Gatekeeper
  class Executor
    def self.call(capability:, node:, project: nil, requested_by:, parameters: {})
      operation = nil
      capability_name = capability.to_s
      capability_class = CapabilityRegistry.fetch!(capability_name)

      operation = GatekeeperOperation.create!(
        gatekeeper_node: node,
        gatekeeper_project: project,
        capability: capability_name,
        requested_by: requested_by.to_s,
        parameters: parameters.to_h,
        status: "running",
        started_at: Time.current
      )

      result = capability_class.call(node:, project:, parameters: parameters.to_h)

      operation.update!(
        status: "succeeded",
        command: result[:command],
        output: result[:output],
        exit_status: result[:exit_status],
        result: result.except(:command, :output, :exit_status),
        completed_at: Time.current
      )

      operation
    rescue StandardError => e
      if operation
        operation.update!(
          status: "failed",
          error_class: e.class.name,
          error_message: e.message,
          completed_at: Time.current
        )

        knowledge = KnowledgeService.find_for_failure(operation:, error: e)
        ticket = SupportTicketService.open_for_failure!(
          operation: operation,
          error: e,
          knowledge_articles: knowledge
        )

        operation.update!(
          result: operation.result.to_h.merge(
            "support_ticket_id" => ticket.id,
            "support_ticket_number" => ticket.number,
            "kb_article_ids" => knowledge.map(&:article_id)
          )
        )
      end

      raise
    end
  end
end
