# frozen_string_literal: true
require "digest"
require "json"

# In-process inference. Extend these methods to add new scoring, retrieval,
# planning or language methods without introducing another server or executor.
module NevaehInference
  extend ActiveSupport::Concern
  STOP_WORDS = %w[a an and are as at be by for from in is it of on or our the this to we with your].freeze

  def infer(format:, context:)
    raise ArgumentError, "This inference model is disabled" unless enabled?
    validate_inference_definition!
    normalized = normalize_inference_context(format: format, context: context)
    terms = extract_inference_terms(normalized.fetch("topic"))
    candidates = inference_candidates(format: format.to_s, context: context.transform_keys(&:to_s))
    ranked = rank_inference_candidates(candidates: candidates, terms: terms)
    chosen = ranked.first
    blocks = chosen ? chosen.fetch("templates") : NevaehIntelligences::WritingEngine::DEFAULTS.fetch(format.to_s)
    text = realize_inference_plan(blocks: blocks, context: normalized, format: format.to_s)
    {"text" => text, "format" => format.to_s, "provider" => "inference", "draft" => true,
      "model_id" => id, "model_name" => name, "model_sha256" => inference_fingerprint,
      "matched_rule" => chosen&.fetch("id"), "match_score" => chosen&.fetch("score") || 0,
      "fallback" => chosen.nil?, "context" => normalized,
      "matches" => ranked.first(5).map { |candidate| candidate.slice("id", "score", "matched_terms") }}
  end

  def normalize_inference_context(format:, context:)
    NevaehIntelligences::WritingEngine.new(format: format, context: context).normalized_context
  end

  def extract_inference_terms(text)
    words = text.to_s.downcase.scan(/[\p{L}\p{N}]+/).first(256)
    synonyms = lexicon.each_with_object({}) do |(canonical, variants), map|
      variants.each { |variant| map[variant.downcase] = canonical.downcase }
    end
    words.map { |word| synonyms.fetch(word, word) }.reject { |word| STOP_WORDS.include?(word) }.uniq
  end

  def inference_candidates(format:, context:)
    configured = rules.select { |rule| rule["format"] == format && Array(rule["requires"]).all? { |field| context[field].to_s.present? } }
    demonstrated = examples.each_with_index.filter_map do |example, index|
      next unless example["format"] == format
      {"id" => "example_#{index + 1}", "format" => format, "keywords" => extract_inference_terms(example.fetch("topic")), "templates" => example.fetch("templates"), "weight" => 1}
    end
    configured + demonstrated
  end

  def rank_inference_candidates(candidates:, terms:)
    candidates.filter_map do |candidate|
      keywords = candidate.fetch("keywords").flat_map { |word| extract_inference_terms(word) }.uniq
      matched = keywords & terms
      next if keywords.any? && matched.empty?
      coverage = keywords.empty? ? 0.0 : matched.length.to_f / keywords.length
      candidate.merge("score" => (coverage * candidate.fetch("weight", 1)).round(4), "matched_terms" => matched)
    end.sort_by { |candidate| [-candidate.fetch("score"), candidate.fetch("id")] }
  end

  def realize_inference_plan(blocks:, context:, format:)
    blocks.map { |block| block.gsub(/\{([^{}]+)\}/) { context.fetch(Regexp.last_match(1)).strip } }.join(format == "caption" ? " " : "\n\n")
  end

  def inference_fingerprint
    Digest::SHA256.hexdigest(JSON.generate({"rules" => rules, "examples" => examples, "lexicon" => lexicon}))
  end

  def validate_inference_definition!
    raise ArgumentError, "Use up to 200 rules and 200 examples" unless rules.is_a?(Array) && rules.length <= 200 && examples.is_a?(Array) && examples.length <= 200
    ids = []
    rules.each do |rule|
      raise ArgumentError, "Each rule needs an ID, format, keywords and templates" unless rule.is_a?(Hash) && (rule.keys - %w[id format keywords templates weight requires]).empty?
      rule_id = rule["id"]
      raise ArgumentError, "Rule IDs must be unique lowercase names" unless rule_id.is_a?(String) && rule_id.match?(/\A[a-z][a-z0-9_]{0,60}\z/) && !ids.include?(rule_id)
      ids << rule_id
      keywords = rule["keywords"]
      raise ArgumentError, "Use up to 40 keyword phrases per rule" unless keywords.is_a?(Array) && keywords.length <= 40 && keywords.all? { |value| value.is_a?(String) && value.length.between?(1, 100) }
      raise ArgumentError, "Rule weight must be between 0 and 10" unless rule.fetch("weight", 1).is_a?(Numeric) && rule.fetch("weight", 1).between?(0, 10)
      required = rule.fetch("requires", [])
      raise ArgumentError, "Unknown required context field" unless required.is_a?(Array) && (required - NevaehIntelligences::WritingEngine::TOKENS).empty?
      validate_inference_blocks!(rule)
    end
    examples.each do |example|
      raise ArgumentError, "Examples need a format, topic and template blocks" unless example.is_a?(Hash) && example.keys.sort == %w[format templates topic] && example["topic"].is_a?(String) && example["topic"].length.between?(1, 4000)
      validate_inference_blocks!(example)
    end
    raise ArgumentError, "Lexicon must contain up to 200 terms with up to 20 one-word synonyms each" unless lexicon.is_a?(Hash) && lexicon.length <= 200 && lexicon.all? { |key, values| key.is_a?(String) && key.match?(/\A[\p{L}\p{N}]{1,60}\z/) && values.is_a?(Array) && values.length <= 20 && values.all? { |value| value.is_a?(String) && value.match?(/\A[\p{L}\p{N}]{1,60}\z/) } }
    raise ArgumentError, "Inference definition exceeds 250 KB" if JSON.generate([rules, examples, lexicon]).bytesize > 250000
    true
  end

  def validate_inference_blocks!(entry)
    raise ArgumentError, "Add at least one template block" unless entry["templates"].is_a?(Array) && entry["templates"].any?
    NevaehIntelligences::WritingEngine.validate_profile!(entry.slice("format", "templates"))
  end
end
