# frozen_string_literal: true
module NevaehNeuralLanguage
  extend ActiveSupport::Concern
  def neural_reply(prompt:, history: [], max_tokens: 64, temperature: 0.6)
    raise ArgumentError, 'This language model is disabled' unless enabled?
    checkpoint = active_checkpoint
    raise ArgumentError, 'Train and activate a passing checkpoint first' unless checkpoint && checkpoint.status == 'active' && checkpoint.nevaeh_language_model_id == id
    expected = Digest::SHA256.hexdigest(NevaehIntelligences::CanonicalJson.dump(checkpoint.weights))
    raise ArgumentError, 'Checkpoint checksum mismatch' unless checkpoint.sha256 == expected
    past = history.last(3).map { |turn| "User: #{turn.prompt}\nNevaeh: #{turn.response}" }.join("\n")
    network = NevaehIntelligences::Neural::Network.new(checkpoint.weights)
    result = network.generate(prompt: [past, "User: #{prompt}\nNevaeh:"].reject(&:empty?).join("\n").last(8000), max_tokens: max_tokens, temperature: temperature)
    raise ArgumentError, 'This checkpoint produced no reply; add examples and retrain' if result['text'].blank?
    result.merge('model_id' => id, 'checkpoint_id' => checkpoint.id, 'draft' => true)
  end
  def available_to?(actor)
    visibility == 'shared' || (actor&.persisted? && %w[admin super_admin].include?(actor.role))
  end
end
