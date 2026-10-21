# frozen_string_literal: true
require 'digest'
require 'json'
require 'time'

module NevaehIntelligences
  # Review-only policy evidence. Neither KB metadata nor this proof grants execution.
  module Studio203NativeKbPolicyEvidenceV7a
    class ReviewRequired < StandardError; end
    module_function
    CAPABILITY = 'studio.capabilities.discovery'
    TRACKING = 'STUDIO-203'
    DIGEST = /\A[0-9a-f]{64}\z/

    # approval_registry must be separately controlled; no default registry exists.
    # An ordinary KB article never supplies its own trust anchor.
    def verify(ticket:, structured:, acceptance_sha256:, resolver: NevaehOrchestration::KnowledgeResolver,
               approval_registry: nil, clock: -> { Time.now.utc })
      raise ReviewRequired, 'approval registry unavailable' unless approval_registry.is_a?(Hash) && !approval_registry.empty?
      raise ReviewRequired, 'invalid acceptance digest' unless acceptance_sha256.to_s.match?(DIGEST)
      raise ReviewRequired, 'invalid ticket' unless ticket.respond_to?(:persisted?) && ticket.persisted? && ticket.respond_to?(:id)
      fields = ticket.extra_fields.to_h.deep_stringify_keys
      raise ReviewRequired, 'ticket identity mismatch' unless fields.dig('project_tracking', 'key') == TRACKING
      expected = Digest::SHA256.hexdigest(JSON.generate(structured))
      raise ReviewRequired, 'acceptance mismatch' unless expected == acceptance_sha256
      articles = resolver.for(capability: CAPABILITY)
      raise ReviewRequired, 'native KB resolver returned invalid shape' unless articles.is_a?(Array)
      valid = articles.filter_map do |article|
        next unless article.respond_to?(:persisted?) && article.persisted?
        next unless article.respond_to?(:id) && article.respond_to?(:metadata)
        meta = article.metadata
        next unless meta.is_a?(Hash)
        meta = meta.deep_stringify_keys
        next unless [meta['nevaeh_capability'], meta['gatekeeper_capability'], meta['capability']].include?(CAPABILITY)
        next unless meta['policy_status'] == 'approved' && meta['policy_scope'] == 'review_only'
        next unless meta['policy_tracking_key'] == TRACKING && meta['acceptance_sha256'] == acceptance_sha256
        next unless meta['policy_version'].to_s.match?(/\A[1-9][0-9]*\z/)
        next unless meta['policy_approval_id'].is_a?(String) && !meta['policy_approval_id'].empty?
        next unless meta['policy_digest'].to_s.match?(DIGEST)
        next unless meta['policy_valid_until'].is_a?(String)
        begin
          expiry = Time.iso8601(meta['policy_valid_until'])
          next unless expiry > clock.call
        rescue ArgumentError
          next
        end
        next if meta['policy_revoked'] != false
        next unless article.respond_to?(:article_type) && %w[guide reference].include?(article.article_type.to_s)
        registry_entry = approval_registry[meta['policy_approval_id']]
        next unless registry_entry.is_a?(Hash)
        registry_entry = registry_entry.deep_stringify_keys
        next unless registry_entry['policy_digest'] == meta['policy_digest']
        next unless registry_entry['article_id'].to_s == article.id.to_s
        next unless registry_entry['version'].to_s == meta['policy_version'].to_s
        next unless registry_entry['status'] == 'approved'
        next unless registry_entry['capability'] == CAPABILITY
        [article, meta]
      end
      raise ReviewRequired, 'missing, conflicting, revoked or unanchored KB policy' unless valid.length == 1
      article, meta = valid.first
      {'verified' => true, 'status' => 'allow_review_only', 'ticket_id' => ticket.id,
       'tracking_key' => TRACKING, 'acceptance_sha256' => acceptance_sha256,
       'policy_id' => "dymond_kb_article:#{article.id}:v#{meta.fetch('policy_version')}",
       'policy_sha256' => meta.fetch('policy_digest'),
       'approval_reference' => meta.fetch('policy_approval_id'),
       'execution_authorized' => false, 'human_review_required' => true}
    rescue NoMethodError, TypeError
      raise ReviewRequired, 'KB evidence malformed'
    end
  end
end
