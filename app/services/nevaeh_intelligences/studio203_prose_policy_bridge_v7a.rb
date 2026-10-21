# frozen_string_literal: true
require 'digest'
require 'json'

module NevaehIntelligences
  # Closed-vocabulary prose interpretation + fail-closed KB policy boundary.
  # This does NOT implement general natural-language reasoning or real KB lookup.
  module Studio203ProsePolicyBridgeV7a
    class ReviewRequired < StandardError; end
    module_function
    TRACKING_KEY = 'STUDIO-203'
    PROSE_FIELD = 'studio203_plain_english_acceptance'
    RULE_SENTENCES = {
      'include only published capabilities' => ['require_published', true],
      'include published and unpublished capabilities' => ['require_published', false],
      'exclude disabled capabilities' => ['include_disabled', false],
      'include disabled capabilities' => ['include_disabled', true]
    }.freeze

    # Default is intentional denial: no actual KB policy connector has been verified.
    module NoVerifiedKbAdapter
      module_function
      def verify(**)
        raise ReviewRequired, 'KB policy verification unavailable; review required'
      end
    end

    def interpret(ticket:)
      raise ReviewRequired, 'persisted ticket required' unless ticket.respond_to?(:persisted?) && ticket.persisted?
      fields = ticket.extra_fields.to_h.deep_stringify_keys
      raise ReviewRequired, 'wrong ticket' unless fields.dig('project_tracking', 'key') == TRACKING_KEY
      prose = fields[PROSE_FIELD]
      raise ReviewRequired, 'acceptance criteria must be an array of two sentences' unless prose.is_a?(Array) && prose.length == 2
      rules = {}
      prose.each do |sentence|
        raise ReviewRequired, 'invalid acceptance sentence' unless sentence.is_a?(String) && sentence.bytesize.between?(8, 180)
        normalized = sentence.strip.downcase.gsub(/\s+/, ' ').sub(/\.$/, '')
        pair = RULE_SENTENCES[normalized]
        raise ReviewRequired, 'unsupported or ambiguous prose requires human review' unless pair
        name, value = pair
        raise ReviewRequired, 'duplicate/contradictory rule requires review' if rules.key?(name)
        rules[name] = value
      end
      raise ReviewRequired, 'incomplete requirements' unless rules.keys.sort == %w[include_disabled require_published]
      {'schema_version' => 1, 'requirements' => %w[require_published include_disabled].map { |k| {'rule' => k, 'value' => rules.fetch(k)} }}
    rescue NoMethodError, TypeError
      raise ReviewRequired, 'malformed ticket fields'
    end

    def evaluate(ticket:, kb_adapter: NoVerifiedKbAdapter)
      structured = interpret(ticket: ticket)
      acceptance_digest = Digest::SHA256.hexdigest(JSON.generate(structured))
      proof = kb_adapter.verify(ticket: ticket, structured: structured, acceptance_sha256: acceptance_digest)
      raise ReviewRequired, 'missing verified KB proof' unless proof.is_a?(Hash)
      raise ReviewRequired, 'KB proof not verified' unless proof['verified'] == true && proof['status'] == 'allow_review_only'
      raise ReviewRequired, 'KB proof ticket mismatch' unless proof['ticket_id'] == ticket.id && proof['tracking_key'] == TRACKING_KEY
      raise ReviewRequired, 'KB proof acceptance mismatch' unless proof['acceptance_sha256'] == acceptance_digest
      raise ReviewRequired, 'KB proof missing versioned policy evidence' unless proof['policy_id'].is_a?(String) && !proof['policy_id'].empty? && proof['policy_sha256'].to_s.match?(/\A[0-9a-f]{64}\z/)
      raise ReviewRequired, 'KB proof cannot grant execution' unless proof['execution_authorized'] == false && proof['human_review_required'] == true
      {'structured_acceptance' => structured, 'acceptance_sha256' => acceptance_digest,
       'policy_id' => proof['policy_id'], 'policy_sha256' => proof['policy_sha256'],
       'kb_policy_verified' => true, 'execution_authorized' => false,
       'requires_human_review' => true, 'interpretation_mode' => 'closed_vocabulary_exact_sentences'}
    end

    # No database mutation: use a bounded proxy ticket for the existing decision bridge.
    def preview(ticket:, kb_adapter: NoVerifiedKbAdapter, planner: GithubDevelopmentPlanV7a,
                work_order_reader: WorkOrder, author: Studio203RepositoryAwareAuthoringV7a,
                root: Rails.root.to_s)
      verdict = evaluate(ticket: ticket, kb_adapter: kb_adapter)
      fields = ticket.extra_fields.to_h.deep_stringify_keys.merge('studio203_acceptance' => verdict.fetch('structured_acceptance'))
      proxy = TicketProxy.new(ticket, fields)
      output = Studio203TicketDecisionBridgeV7a.preview(ticket: proxy, root: root,
        planner: NativePlannerTransport.new(planner),
        work_order_reader: NativeWorkOrderTransport.new(work_order_reader), author: author)
      output.merge(verdict).merge('kb_policy_verified' => true, 'requires_human_review' => true,
                                 'execution_authorized' => false)
    end

    def generate(ticket:, destination:, kb_adapter: NoVerifiedKbAdapter, planner: GithubDevelopmentPlanV7a,
                 work_order_reader: WorkOrder, author: Studio203RepositoryAwareAuthoringV7a,
                 root: Rails.root.to_s)
      checked = preview(ticket: ticket, kb_adapter: kb_adapter, planner: planner,
        work_order_reader: work_order_reader, author: author, root: root)
      # Must use verified, derived spec; no second policy evaluation that could change policy midway.
      output = author.generate(ticket: ticket, changes: checked.fetch('change_specification'),
        destination: destination, root: root, planner: planner)
      output.merge(checked).merge('generated_artifacts_review_only' => true)
    end

    # A derived-criteria proxy must not masquerade as a persisted ActiveRecord ticket
    # when delegating to the native development planner or work order reader.
    module NativeTicketTransport
      module_function

      def unwrap(ticket)
        return ticket unless ticket.instance_of?(TicketProxy)
        original = ticket.original
        # Keep older injected, lightweight test contracts compatible. The native
        # path ALWAYS requires a genuine persisted Marlon::Ticket.
        return ticket unless original.is_a?(Marlon::Ticket)
        raise ReviewRequired, 'original ticket not persisted' unless original.persisted?
        raise ReviewRequired, 'proxy ticket identity mismatch' unless original.id == ticket.id
        original_fields = original.extra_fields.to_h.deep_stringify_keys
        proxy_fields = ticket.extra_fields.to_h.deep_stringify_keys
        raise ReviewRequired, 'proxy fields changed outside derived acceptance' unless
          (proxy_fields.keys - original_fields.keys) == ['studio203_acceptance'] &&
          original_fields.all? { |key, value| proxy_fields[key] == value }
        original
      end
    end

    class NativePlannerTransport
      def initialize(delegate) = @delegate = delegate
      def from_ticket(ticket:)
        @delegate.from_ticket(ticket: NativeTicketTransport.unwrap(ticket))
      end
    end

    class NativeWorkOrderTransport
      def initialize(delegate) = @delegate = delegate
      def read!(ticket:)
        @delegate.read!(ticket: NativeTicketTransport.unwrap(ticket))
      end
    end

    class TicketProxy
      attr_reader :id, :extra_fields, :original
      def initialize(original, fields)
        @original = original
        @id = original.id
        @extra_fields = fields
      end
      def persisted? = @original.persisted?
    end
  end
end
