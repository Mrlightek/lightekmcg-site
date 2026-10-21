# frozen_string_literal: true
require 'json'
require 'digest'

module NevaehIntelligences
  # Converts explicit *structured* ticket requirements to a bounded code-authoring spec.
  # Does not interpret arbitrary prose, consult KB, authorize execution, or dispatch.
  module Studio203TicketDecisionBridgeV7a
    class Rejected < StandardError; end
    module_function
    TRACKING_KEY = 'STUDIO-203'
    RULES = %w[require_published include_disabled].freeze
    FIELD = 'studio203_acceptance'

    def decisions(ticket:, work_order_reader: WorkOrder)
      raise Rejected, 'persisted ticket required' unless ticket.respond_to?(:persisted?) && ticket.persisted?
      fields = ticket.extra_fields.to_h.deep_stringify_keys
      raise Rejected, 'wrong tracking key' unless fields.dig('project_tracking', 'key') == TRACKING_KEY
      order = work_order_reader.read!(ticket: ticket)
      raise Rejected, 'invalid native work order' unless order.is_a?(Hash)
      order = order.deep_stringify_keys
      raise Rejected, 'wrong work order' unless order['work_type'] == 'build' && order['intent_key'] == 'github:Mrlightek/lightekmcg-site:STUDIO-203'
      policy = order['execution_policy']
      raise Rejected, 'unsafe execution policy' unless policy.is_a?(Hash) && policy['environment'] == 'test' && policy['approval'] == 'gatekeeper' && policy['execution_enabled'] == false && policy['production_allowed'] == false && policy['requires_human_release_approval'] == true
      structured = fields[FIELD]
      raise Rejected, 'structured acceptance missing' unless structured.is_a?(Hash) && structured.keys.sort == %w[requirements schema_version]
      raise Rejected, 'unsupported acceptance version' unless structured['schema_version'] == 1
      requirements = structured['requirements']
      raise Rejected, 'requirements must be bounded array' unless requirements.is_a?(Array) && requirements.length.between?(2, 8)
      decisions = {}
      requirements.each do |requirement|
        raise Rejected, 'invalid requirement structure' unless requirement.is_a?(Hash) && requirement.keys.sort == %w[rule value]
        rule = requirement['rule']
        value = requirement['value']
        raise Rejected, 'unsupported rule requires review' unless RULES.include?(rule)
        raise Rejected, 'nonboolean rule requires review' unless value == true || value == false
        raise Rejected, 'duplicate or contradictory rule requires review' if decisions.key?(rule)
        decisions[rule] = value
      end
      raise Rejected, 'incomplete rule set requires review' unless decisions.keys.sort == RULES.sort
      RULES.to_h { |rule| [rule, decisions.fetch(rule)] }
    rescue NoMethodError, TypeError => e
      raise Rejected, "malformed ticket contract: #{e.class.name}"
    end

    def preview(ticket:, root: Rails.root.to_s, planner: GithubDevelopmentPlanV7a,
                work_order_reader: WorkOrder, author: Studio203RepositoryAwareAuthoringV7a)
      specification = decisions(ticket: ticket, work_order_reader: work_order_reader)
      upstream = author.preview(ticket: ticket, changes: specification, root: root, planner: planner)
      upstream.merge('ticket_derived_decisions' => true,
                     'decision_origin' => 'structured_ticket_acceptance_only',
                     'acceptance_sha256' => Digest::SHA256.hexdigest(JSON.generate(specification)),
                     'kb_policy_verified' => false,
                     'requires_human_review' => true,
                     'autonomous_natural_language_inference' => false)
    end

    def generate(ticket:, destination:, root: Rails.root.to_s, planner: GithubDevelopmentPlanV7a,
                 work_order_reader: WorkOrder, author: Studio203RepositoryAwareAuthoringV7a)
      preflight = preview(ticket: ticket, root: root, planner: planner,
                          work_order_reader: work_order_reader, author: author)
      output = author.generate(ticket: ticket, changes: preflight.fetch('change_specification'),
                               destination: destination, root: root, planner: planner)
      output.merge('ticket_derived_decisions' => true,
                   'decision_origin' => 'structured_ticket_acceptance_only',
                   'acceptance_sha256' => preflight.fetch('acceptance_sha256'),
                   'kb_policy_verified' => false,
                   'requires_human_review' => true,
                   'autonomous_natural_language_inference' => false)
    end
  end
end
