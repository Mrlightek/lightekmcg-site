# frozen_string_literal: true
class NevaehConversation < ApplicationRecord
  belongs_to :user
  belongs_to :nevaeh_language_model
  has_many :turns, class_name: 'NevaehConversationTurn', dependent: :destroy
  validates :title, length: {maximum: 160}
  def reply!(actor:, prompt:, request_key:)
    raise ArgumentError, 'Conversation belongs to another account' unless actor&.persisted? && user_id == actor.id
    raise ArgumentError, 'Model is internal to administrators' unless nevaeh_language_model.available_to?(actor)
    raise ArgumentError, 'Message must contain 1–4000 characters' unless prompt.is_a?(String) && prompt.strip.length.between?(1, 4000)
    raise ArgumentError, 'Request key required' unless request_key.to_s.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
    with_lock do
      return turns.find_by!(request_key: request_key) if turns.exists?(request_key: request_key)
      result = nevaeh_language_model.neural_reply(prompt: prompt, history: turns.order(id: :desc).limit(3).to_a.reverse)
      turns.create!(request_key: request_key, prompt: prompt, response: result.fetch('text'), checkpoint_id: result.fetch('checkpoint_id'), evidence: result.except('text'))
    end
  end
end
