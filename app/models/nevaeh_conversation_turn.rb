# frozen_string_literal: true
class NevaehConversationTurn < ApplicationRecord
  belongs_to :nevaeh_conversation
  validates :request_key, uniqueness: {scope: :nevaeh_conversation_id}
  validates :prompt, :response, presence: true
end
