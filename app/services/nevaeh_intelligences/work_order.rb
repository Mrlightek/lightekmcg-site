# frozen_string_literal: true

module NevaehIntelligences
  # A Marlon::Ticket is the work order. The JSON contract lives in extra_fields,
  # so we do not introduce another ticketing database or execution plane.
  class WorkOrder
    class Invalid < StandardError; end
    VERSION = 1
    TYPES = %w[create read update delete fix build test deploy].freeze
    PROOF_INTENT = "studio.project.create"

    def self.template(work_type: "create", intent_key: PROOF_INTENT)
      {
        "version" => VERSION,
        "work_type" => work_type,
        "intent_key" => intent_key,
        "objective" => "",
        "inputs" => {},
        "acceptance_criteria" => [],
        "execution_policy" => { "environment" => "development", "approval" => "gatekeeper" }
      }
    end

    def self.attach!(ticket:, attributes:)
      raise Invalid, "Ticket must be saved and unresolved" unless ticket.persisted? && ticket.status != "resolved"
      order = validate!(attributes)
      ticket.with_lock do
        data = ticket.extra_fields.to_h.deep_stringify_keys
        raise Invalid, "Ticket has already been reserved or dispatched" if data.dig("nevaeh", "work_item_id").present? || data.dig("nevaeh", "execution_status").present?
        data["nevaeh_work_order"] = order
        ticket.update!(extra_fields: data)
        ticket.log!(action: "nevaeh_work_order_registered", detail: JSON.generate(order))
      end
      order
    end

    def self.read!(ticket:)
      validate!(ticket.extra_fields.to_h.deep_stringify_keys.fetch("nevaeh_work_order") do
        raise Invalid, "Ticket has no Nevaeh work order"
      end)
    end

    def self.preview!(ticket:)
      order = read!(ticket: ticket)
      NevaehIntelligences::Dispatch.call(intent_key: order.fetch("intent_key"), payload: order.fetch("inputs"), execute: false)
    end

    def self.dispatch!(ticket:, actor:)
      order = read!(ticket: ticket)
      if order["intent_key"] == "ticket.structured.execute"
        return StructuredExecution.dispatch!(ticket: ticket, actor: actor, explicit: true)
      end
      raise Invalid, "Authenticated actor required" unless actor&.persisted?
      environment = order.dig("execution_policy", "environment")
      raise Invalid, "Work order environment must match Rails environment" unless environment == Rails.env
      # The editable work-order approval value is NOT authoritative human approval.
      # Production enablement needs a separate, trusted server-side approval record.
      raise Invalid, "Production execution requires trusted approval (not yet enabled)" if Rails.env.production?
      # V1 deliberately allows only the capability already proven in production.
      raise Invalid, "This work type has no verified executor yet" unless order.fetch("intent_key") == PROOF_INTENT && order.fetch("work_type") == "create"
      NevaehIntelligences::TicketExecution.dispatch!(ticket: ticket, actor: actor, payload: order.fetch("inputs"))
    end

    def self.validate!(attributes)
      order = attributes.to_h.deep_stringify_keys
      raise Invalid, "Unsupported work-order version" unless order["version"].to_i == VERSION
      raise Invalid, "Unsupported work type" unless TYPES.include?(order["work_type"])
      raise Invalid, "intent_key is required" if order["intent_key"].to_s.strip.empty?
      raise Invalid, "objective is required" if order["objective"].to_s.strip.empty?
      raise Invalid, "inputs must be a JSON object" unless order["inputs"].is_a?(Hash)
      criteria = order["acceptance_criteria"]
      raise Invalid, "acceptance_criteria must be a nonempty array of strings" unless criteria.is_a?(Array) && criteria.any? && criteria.all? { |v| v.is_a?(String) && v.strip.present? }
      policy = order["execution_policy"]
      raise Invalid, "execution_policy must be an object" unless policy.is_a?(Hash)
      raise Invalid, "Invalid execution environment" unless %w[development test staging production].include?(policy["environment"])
      raise Invalid, "Invalid approval rule" unless %w[gatekeeper approved].include?(policy["approval"])
      if order["intent_key"] == "ticket.structured.execute"
        raise Invalid, "Structured work order accepts only action sections" unless order["inputs"].keys == ["sections"]
        compiled = StructuredTicket.compile(order["inputs"]["sections"])
        raise Invalid, "Structured sections must use the compiled contract" unless compiled == order["inputs"]["sections"]
      end
      if order["intent_key"] == PROOF_INTENT && order["work_type"] == "create"
        raise Invalid, "Studio project name is required" if order.dig("inputs", "name").to_s.strip.empty?
      end
      order
    end
  end
end
