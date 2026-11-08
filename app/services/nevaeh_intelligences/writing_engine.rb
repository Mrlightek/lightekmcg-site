# frozen_string_literal: true
require "json"
require "digest"

module NevaehIntelligences
  # Shared by Studio and the control center. Templates are data, never Ruby/ERB.
  class WritingEngine
    FORMATS = %w[caption post script description].freeze
    TOKENS = %w[topic audience goal obstacle setting protagonist companion call_to_action facts].freeze
    DEFAULTS = {
      "caption" => ["{topic}.", "{goal}.", "{call_to_action}"],
      "post" => ["Let's talk about {topic}.", "For {audience}, the goal is clear: {goal}.", "The challenge: {obstacle}.", "{facts}", "{call_to_action}"],
      "description" => ["Explore {topic}.", "Created for {audience}, this project focuses on one goal: {goal}.", "{facts}", "{call_to_action}"],
      "script" => ["INT. {setting} — DAY", "{protagonist}: We need to {goal}.", "{companion}: First, we have to deal with {obstacle}.", "{protagonist}: Then let's start with what we know about {topic}.", "{companion}: {facts}", "{protagonist}: We handle that first, then take the next step together."]
    }.freeze

    def self.validate_profile!(profile)
      raise ArgumentError, "Choose a supported writing format" unless FORMATS.include?(profile["format"])
      templates = profile.fetch("templates", [])
      raise ArgumentError, "Use at most 40 text blocks, each under 2000 characters" unless templates.is_a?(Array) && templates.length <= 40 && templates.all? { |t| t.is_a?(String) && t.length.between?(1, 2000) }
      templates.each do |template|
        unknown = template.scan(/\{([^{}]+)\}/).flatten - TOKENS
        raise ArgumentError, "Unknown template fields: #{unknown.join(', ')}" if unknown.any?
      end
      examples = profile.fetch("examples", [])
      raise ArgumentError, "Use at most 20 examples, each under 4000 characters" unless examples.is_a?(Array) && examples.length <= 20 && examples.all? { |v| v.is_a?(String) && v.length.between?(1, 4000) }
      true
    end

    def self.generate(format:, context:, profile: nil, actor: nil)
      new(format: format, context: context, profile: profile, actor: actor).call
    end

    def initialize(format:, context:, profile: nil, actor: nil)
      @actor = actor
      @format = format.to_s
      raise ArgumentError, "Unsupported writing format" unless FORMATS.include?(@format)
      @profile = profile || {"format" => @format, "provider" => "rules", "templates" => [], "examples" => []}
      self.class.validate_profile!(@profile)
      raise ArgumentError, "Profile format does not match" unless @profile["format"] == @format
      raise ArgumentError, "Context must be an object" unless context.is_a?(Hash)
      supplied = context.transform_keys(&:to_s)
      @supplied_context = supplied
      raise ArgumentError, "Unknown context fields" if (supplied.keys - TOKENS).any?
      raise ArgumentError, "Context values must be text under 4000 characters" unless supplied.values.all? { |v| v.is_a?(String) && v.length <= 4000 }
      raise ArgumentError, "Topic is required" if supplied["topic"].to_s.strip.empty?
      @context = {"audience" => "your audience", "goal" => "bring this idea to life", "obstacle" => "the unresolved problem",
        "setting" => "WORKSPACE", "protagonist" => "LEAD", "companion" => "PARTNER",
        "call_to_action" => "Share your thoughts.", "facts" => "We still need to verify the details."}.merge(supplied.reject { |_k, v| v.strip.empty? })
    end

    def call
      provider = @profile.fetch("provider", "rules")
      text = case provider
      when "rules"
        templates = @profile.fetch("templates", [])
        templates = DEFAULTS.fetch(@format) if templates.empty?
        templates.map { |template| template.gsub(/\{([^{}]+)\}/) { @context.fetch(Regexp.last_match(1)).strip } }.join(@format == "caption" ? " " : "\n\n")
      when "inference"
        model = NevaehInferenceModel.find(@profile.fetch("inference_model_id"))
        raise ArgumentError, "This inference model is disabled" unless model.enabled?
        inference = model.infer(format: @format, context: @supplied_context)
        inference.fetch("text")
      when "neural"
        model = NevaehLanguageModel.find(@profile.fetch("language_model_id"))
        raise ArgumentError, "This model is internal to administrators" unless model.available_to?(@actor)
        inference = model.neural_reply(prompt: "Write a #{@format}. " + CanonicalJSON.dump(@context))
        inference.fetch("text")
      else
        raise ArgumentError, "Unknown writing provider"
      end
      direction = EditorialDirection.apply(text: text, notes: @profile["instructions"], context: @context)
      {"text" => direction[:text], "editorial" => direction.except(:text), "format" => @format, "provider" => provider, "draft" => true,
        "profile_sha256" => Digest::SHA256.hexdigest(JSON.generate(@profile)), "context" => @context}.tap { |result| result["inference"] = inference.except("text", "context") if inference }
    end

    def normalized_context = @context.dup
  end
end
